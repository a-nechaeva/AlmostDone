"""Mapping and transaction tests without a running PostgreSQL server."""
import copy
from decimal import Decimal
from types import SimpleNamespace

import pytest

from almostdone_server.errors import StorageUnavailable, StorageValueError
from almostdone_server.repositories.postgres import PostgresStore, Transaction
from almostdone_server.repositories.records import MemoryRecords
from almostdone_server.services.models import default_user
from almostdone_server.services.state import UserStateService


class Rows(list):
    rowcount = 1

    def fetchone(self):
        return self[0] if self else None


class Database(dict):
    def __init__(self):
        super().__init__()
        self.runtime = {}
        self.queries = []
        self.account = {"id": 1, "pevzner_diet_id": 11}
        self.diets = [
            {"id": 11, "kind": "pevzner", "name": "Стол №15"},
            {"id": 12, "kind": "diet", "name": "Вегетарианство"},
            {"id": 15, "kind": "diet", "name": "Безглютеновая"},
        ]
        self.pantry = [{"code": "egg", "qty_g": Decimal("100.00")}]
        self.metadata = {"state_version": 0, "diabetes": False, "pantry_display": {}, "state_hash": None}

    def execute(self, sql, params=()):
        self.queries.append((sql, params))
        if sql.startswith("SELECT state_version"):
            return Rows([copy.deepcopy(self.metadata)])
        if 'INSERT INTO user_api_state(user_id,state_version' in sql:
            self.metadata = {"state_version": params[1], "diabetes": params[2],
                             "pantry_display": copy.deepcopy(params[3].obj), "state_hash": params[4]}
        if sql.startswith("SELECT id,pevzner"):
            return Rows([self.account])
        if sql.startswith("SELECT name FROM diets"):
            return Rows([self.diets[0]])
        if sql.startswith("SELECT id,kind,name"):
            return Rows(self.diets)
        if sql.startswith("SELECT d.name"):
            return Rows([{"name": "Вегетарианство"}, {"name": "Безглютеновая"}])
        if sql.startswith("SELECT a.code"):
            return Rows([{"code": "milk"}])
        if sql.startswith("SELECT i.code,p.qty_g"):
            return Rows(self.pantry)
        if sql.startswith("SELECT f.recipe_id"):
            return Rows([{"recipe_id": 2}])
        if sql.startswith("SELECT i.code FROM favorite"):
            return Rows([{"code": "egg"}])
        if sql.startswith("SELECT"):
            raise AssertionError(sql)
        return Rows()


def store():
    result = PostgresStore.__new__(PostgresStore)
    result.runtime = MemoryRecords()
    result.catalog = SimpleNamespace(ingredients={"egg": {"grams_per_piece": 50}})
    return result


def test_reads_existing_relations_and_resolves_table_number_instead_of_id():
    repository, db = store(), Database()
    states = UserStateService(repository, repository.catalog)
    state = states.load(db, "1")
    assert state["preferences"] == {
        "food_type": "vegetarian", "excluded_allergens": ["milk"],
        "gluten_free": True, "lactose_free": False, "diabetes": False,
        "diet_table_id": "pevzner_15",
    }
    assert state["pantry"] == {"egg": {"value": 100, "unit": "g"}}
    assert state["favorites"] == {"recipes": ["2"], "ingredients": ["egg"]}
    assert states.load(db, "1")["version"] == 0
    db.pantry[0]["qty_g"] = Decimal("101.00")
    assert states.load(db, "1")["version"] == 1


def test_save_uses_existing_tables_without_ddl_and_maps_preferences():
    repository, db = store(), Database()
    states = UserStateService(repository, repository.catalog)
    state = states.load(db, "1")
    state["pantry"]["egg"] = {"value": 2, "unit": "pcs"}
    states.save(db, "1", state)
    writes = [(sql, params) for sql, params in db.queries if not sql.startswith("SELECT")]
    assert any("INSERT INTO user_pantry" in sql and params[1] == Decimal("100") for sql, params in writes)
    assert any("UPDATE users SET pevzner_diet_id" in sql and params == (11, 1) for sql, params in writes)
    assert {params[1] for sql, params in writes if "INSERT INTO user_diets" in sql} == {12, 15}
    assert all(not sql.startswith(("CREATE", "ALTER", "DROP")) for sql, _ in db.queries)
    assert states.load(db, "1")["pantry"]["egg"] == {"value": 2, "unit": "pcs"}


@pytest.mark.parametrize("value", [1000000, 0.001])
def test_quantities_that_do_not_fit_existing_column_are_rejected(value):
    repository, db = store(), Database()
    states = UserStateService(repository, repository.catalog)
    state = default_user()
    state["pantry"]["egg"] = {"value": value, "unit": "g"}
    with pytest.raises(StorageValueError) as error:
        states.save(db, "1", state)
    assert error.value.field in {"quantity", "preferences.diet_table_id"}
    assert not any("INSERT INTO user_pantry" in sql for sql, _ in db.queries)


def test_missing_diet_is_rejected_instead_of_discarding_preference():
    repository, db = store(), Database()
    states = UserStateService(repository, repository.catalog)
    state = default_user()
    state["preferences"]["diet_table_id"] = "pevzner_11"
    with pytest.raises(StorageValueError) as error:
        states.save(db, "1", state)
    assert error.value.field in {"quantity", "preferences.diet_table_id"}


def test_runtime_state_is_not_published_when_sql_commit_fails(monkeypatch):
    psycopg = pytest.importorskip("psycopg")
    repository = store()
    repository.psycopg, repository.row_factory, repository.dsn = psycopg, None, "unused"
    before = copy.deepcopy(repository.runtime._data)

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            raise psycopg.OperationalError("commit failed")

        def execute(self, *args):
            return Rows()

    monkeypatch.setattr(psycopg, "connect", lambda *args, **kwargs: Connection())
    with pytest.raises(StorageUnavailable) as error:
        with repository.transaction() as db:
            assert isinstance(db, Transaction)
            db.execute("UPDATE user_api_state SET state_version=1 WHERE user_id=1")
    assert str(error.value) == "База данных временно недоступна"
    assert repository.runtime._data == before


@pytest.mark.parametrize("failure_name", ["DeadlockDetected", "LockNotAvailable", "QueryCanceled"])
def test_temporary_sql_failure_rolls_back_runtime_and_maps_to_unavailable(monkeypatch, failure_name):
    psycopg = pytest.importorskip("psycopg")
    repository = store()
    repository.psycopg, repository.row_factory, repository.dsn = psycopg, None, "unused"
    before = copy.deepcopy(repository.runtime._data)

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def execute(self, *args):
            return Rows()

    monkeypatch.setattr(psycopg, "connect", lambda *args, **kwargs: Connection())
    with pytest.raises(StorageUnavailable):
        with repository.transaction() as db:
            db.execute("UPDATE user_api_state SET state_version=1 WHERE user_id=1")
            raise getattr(psycopg.errors, failure_name)("temporary SQL failure")
    assert repository.runtime._data == before
