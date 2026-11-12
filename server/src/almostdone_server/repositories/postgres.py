"""SQL access and row mapping for the existing PostgreSQL schema. No DDL."""
import re
from contextlib import contextmanager
from decimal import Decimal

from ..errors import StorageUnavailable, StorageSchemaError, StorageConflict, StorageValueError
from .records import Transaction


FOOD_DIETS = {"vegetarian": "Вегетарианство", "vegan": "Веганство"}
FLAG_DIETS = {"gluten_free": "Безглютеновая", "lactose_free": "Безлактозная"}


class PostgresStore:
    mode = "postgresql"
    persistent = True

    def check_health(self):
        from ..migrate import migration_files, MIGRATIONS_DIR

        try:
            with self.psycopg.connect(self.dsn, connect_timeout=2,
                                     options='-c statement_timeout=1000 -c lock_timeout=1000') as connection:
                connection.execute('SELECT 1').fetchone()
                for table in (
                    'users', 'user_pantry', 'favorite_ingredients', 'favorite_recipes',
                    'user_diets', 'user_allergens', 'diets', 'allergens', 'ingredients',
                    'ingredient_aliases', 'ingredient_allergens', 'ingredient_categories',
                    'categories', 'recipes', 'recipe_ingredients', 'recipe_steps',
                    'cooking_methods', 'recipe_cooking_methods', 'diet_excluded_allergens',
                    'diet_excluded_categories', 'diet_excluded_methods', 'user_identities',
                    'auth_sessions', 'auth_tokens', 'user_api_state', 'api_idempotency',
                    'api_resources', 'recognition_imports', 'user_all_diets',
                    'user_recipe_visibility', 'recipe_categories', 'recipe_allergens',
                ):
                    connection.execute(f'SELECT * FROM public.{table} LIMIT 0')
                applied = {row[0] for row in connection.execute(
                    'SELECT version FROM public.api_schema_migrations')}
                required = {path.stem for path in migration_files(MIGRATIONS_DIR)}
                if not required <= applied:
                    raise StorageSchemaError('Database migrations are pending')
        except self.psycopg.Error:
            raise StorageUnavailable('Database readiness check failed') from None

    def __init__(self, dsn):
        import psycopg
        from psycopg.rows import dict_row

        self.psycopg, self.row_factory, self.dsn = psycopg, dict_row, dsn
        from .postgres_records import PostgresRecords
        self.runtime = PostgresRecords()

    @contextmanager
    def transaction(self):
        try:
            with self.psycopg.connect(self.dsn, row_factory=self.row_factory, connect_timeout=5) as connection:
                connection.execute("SET LOCAL lock_timeout = '5s'")
                connection.execute("SET LOCAL statement_timeout = '15s'")
                yield Transaction(connection, connection)
        except self.psycopg.OperationalError:
            # This includes deadlocks, lock timeouts and statement timeouts.
            # They are temporary storage failures, mapped to HTTP 503 by the API.
            raise StorageUnavailable("База данных временно недоступна") from None
        except (self.psycopg.errors.UndefinedTable, self.psycopg.errors.UndefinedColumn):
            raise StorageSchemaError("Схема БД не соответствует db/schema.sql") from None
        except self.psycopg.errors.ForeignKeyViolation:
            raise StorageConflict("Связанные данные изменились") from None

    def identity(self, db, login, password_marker):
        return db.execute(
            "INSERT INTO users(login,password_hash) VALUES (%s,%s) "
            "ON CONFLICT (login) DO UPDATE SET login=EXCLUDED.login RETURNING id,password_hash",
            (login, password_marker),
        ).fetchone()

    def oauth_identity(self, db, provider, subject, login, marker):
        # The same verified identity must serialize even when no account exists yet.
        db.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s,0))", (provider + ':' + subject,))
        row = db.execute("SELECT user_id FROM user_identities WHERE provider=%s AND provider_subject=%s",
                         (provider, subject)).fetchone()
        if row:
            return str(row["user_id"])
        # Preserve IDs and user data for accounts created before user_identities.
        row = self.identity(db, login, marker)
        if row["password_hash"] != marker:
            from ..errors import APIError
            raise APIError(409, "context_changed", "Логин занят другой учётной записью")
        db.execute("INSERT INTO user_identities(user_id,provider,provider_subject) VALUES (%s,%s,%s)",
                   (row["id"], provider, subject))
        return str(row["id"])

    def api_state(self, db, user_id):
        # user() already holds the account lock: every API command uses the same
        # lock order (user, then dependent state/session rows) across processes.
        db.execute("INSERT INTO user_api_state(user_id) VALUES (%s) ON CONFLICT DO NOTHING", (user_id,))
        return db.execute("SELECT state_version,diabetes,pantry_display,state_hash FROM user_api_state WHERE user_id=%s",
                          (user_id,)).fetchone()

    def save_api_state(self, db, user_id, state, state_hash):
        from psycopg.types.json import Jsonb
        db.execute("""
            INSERT INTO user_api_state(user_id,state_version,diabetes,pantry_display,state_hash)
            VALUES (%s,%s,%s,%s,%s) ON CONFLICT (user_id) DO UPDATE
            SET state_version=EXCLUDED.state_version,diabetes=EXCLUDED.diabetes,
                pantry_display=EXCLUDED.pantry_display,state_hash=EXCLUDED.state_hash,updated_at=clock_timestamp()
        """, (user_id, state["version"], state["preferences"]["diabetes"], Jsonb(state["pantry"]), state_hash))

    @staticmethod
    def _diet_ids(db):
        names = {name: key for key, name in {**FOOD_DIETS, **FLAG_DIETS}.items()}
        result = {}
        for row in db.execute('SELECT id, kind, name FROM diets'):
            if row['kind'] == 'diet' and row['name'] in names:
                result[row['name']] = names[row['name']]
            elif row['kind'] == 'pevzner':
                match = re.fullmatch(r'Стол №\s*(\d+)', row['name'])
                if match and 1 <= int(match[1]) <= 15:
                    result[row['name']] = 'pevzner_' + str(int(match[1]))
        return result

    def dietary_support(self, db):
        return set(self._diet_ids(db).values())

    def dietary_visibility(self, db, user_id):
        active = db.execute('SELECT EXISTS(SELECT 1 FROM user_all_diets WHERE user_id=%s) AS active',
                            (int(user_id),)).fetchone()['active']
        if not active:
            return None
        diet_ids = self._diet_ids(db)
        rows = db.execute("""
            SELECT v.recipe_id, v.is_hidden, v.violated_diets,
                   ARRAY(SELECT i.code FROM ingredients i
                         WHERE i.name = ANY(v.skip_optional) ORDER BY i.code) AS skip_optional_ids
            FROM user_recipe_visibility v WHERE v.user_id = %s
        """, (int(user_id),))
        return {str(row['recipe_id']): {
            'hidden': row['is_hidden'],
            'restrictions': sorted(diet_ids[name] for name in row['violated_diets'] if name in diet_ids),
            'diet_violation': bool(row['violated_diets']),
            'skip_optional': list(row['skip_optional_ids']),
        } for row in rows}

    def user(self, db, user_id):
        uid = int(user_id)
        account = db.execute("SELECT id,pevzner_diet_id FROM users WHERE id=%s FOR UPDATE", (uid,)).fetchone()
        if account is None:
            return None
        prefs = {}
        state = {"preferences": prefs, "pantry": {}, "favorites": {"recipes": [], "ingredients": []}}
        prefs["excluded_allergens"] = [row["code"] for row in db.execute(
            "SELECT a.code FROM user_allergens u JOIN allergens a ON a.id=u.allergen_id WHERE u.user_id=%s ORDER BY a.code", (uid,))]
        for diet in db.execute("SELECT d.name FROM user_diets u JOIN diets d ON d.id=u.diet_id WHERE u.user_id=%s ORDER BY d.id", (uid,)):
            for value, name in FOOD_DIETS.items():
                if diet["name"] == name:
                    prefs["food_type"] = value
            for flag, name in FLAG_DIETS.items():
                if diet["name"] == name:
                    prefs[flag] = True
        if account["pevzner_diet_id"] is not None:
            diet = db.execute("SELECT name FROM diets WHERE id=%s AND kind='pevzner'", (account["pevzner_diet_id"],)).fetchone()
            match = re.fullmatch(r"Стол №\s*(\d+)", diet["name"]) if diet else None
            if not match or not 1 <= int(match[1]) <= 15:
                raise StorageConflict("Диетический стол БД не представлен в API")
            prefs["diet_table_id"] = f"pevzner_{int(match[1])}"
        for item in db.execute("SELECT i.code,p.qty_g FROM user_pantry p JOIN ingredients i ON i.id=p.ingredient_id WHERE p.user_id=%s", (uid,)):
            code, grams = item["code"], item["qty_g"]
            if grams is None:
                state["pantry"][code] = None
            elif grams > 0:
                quantity = {"value": float(grams), "unit": "g"}
                state["pantry"][code] = quantity
        state["favorites"]["recipes"] = sorted(str(row["recipe_id"]) for row in db.execute(
            "SELECT f.recipe_id FROM favorite_recipes f JOIN recipes r ON r.id=f.recipe_id WHERE f.user_id=%s AND r.author_id IS NULL ORDER BY f.recipe_id", (uid,)))
        state["favorites"]["ingredients"] = [row["code"] for row in db.execute(
            "SELECT i.code FROM favorite_ingredients f JOIN ingredients i ON i.id=f.ingredient_id WHERE f.user_id=%s ORDER BY i.code", (uid,))]
        return state

    def save(self, db, user_id, state):
        uid = int(user_id)
        prefs = state["preferences"]
        diets = list(db.execute("SELECT id,kind,name FROM diets"))
        selected = []
        names = ([FOOD_DIETS[prefs["food_type"]]] if prefs["food_type"] in FOOD_DIETS else [])
        names += [name for flag, name in FLAG_DIETS.items() if prefs[flag]]
        for name in names:
            diet = next((d for d in diets if d["kind"] == "diet" and d["name"] == name), None)
            if diet is None:
                raise StorageValueError("Диета отсутствует в справочнике БД", "preferences")
            selected.append(diet["id"])
        table_id = None
        if prefs["diet_table_id"]:
            number = int(prefs["diet_table_id"].split("_")[1])
            diet = next((d for d in diets if d["kind"] == "pevzner" and re.fullmatch(rf"Стол №\s*{number}", d["name"])), None)
            if diet is None:
                raise StorageValueError("Диетический стол отсутствует в справочнике БД", "preferences.diet_table_id")
            table_id = diet["id"]
        db.execute("DELETE FROM user_pantry WHERE user_id=%s", (uid,))
        for code, quantity in state["pantry"].items():
            if quantity is not None and quantity["unit"] != "g":
                raise StorageValueError("user_pantry хранит массу в граммах", "quantity")
            grams = Decimal(str(quantity["value"])) if quantity is not None else None
            if quantity is not None:
                if not grams.is_finite() or grams < 0 or grams > Decimal("999999.99") or grams != grams.quantize(Decimal("0.01")):
                    raise StorageValueError("БД поддерживает количество до 999999.99 г с точностью 0.01 г", "quantity")
            result = db.execute("INSERT INTO user_pantry(user_id,ingredient_id,qty_g) SELECT %s,id,%s FROM ingredients WHERE code=%s", (uid, grams, code))
            if result.rowcount != 1:
                raise StorageConflict("Каталог ингредиентов изменился")
        db.execute("DELETE FROM favorite_recipes WHERE user_id=%s AND recipe_id IN (SELECT id FROM recipes WHERE author_id IS NULL)", (uid,))
        for rid in state["favorites"]["recipes"]:
            db.execute("INSERT INTO favorite_recipes(user_id,recipe_id) VALUES (%s,%s)", (uid, int(rid)))
        db.execute("DELETE FROM favorite_ingredients WHERE user_id=%s", (uid,))
        for code in state["favorites"]["ingredients"]:
            db.execute("INSERT INTO favorite_ingredients(user_id,ingredient_id) SELECT %s,id FROM ingredients WHERE code=%s", (uid, code))
        db.execute("DELETE FROM user_allergens WHERE user_id=%s", (uid,))
        for code in prefs["excluded_allergens"]:
            result = db.execute("INSERT INTO user_allergens(user_id,allergen_id) SELECT %s,id FROM allergens WHERE code=%s", (uid, code))
            if result.rowcount != 1:
                raise StorageValueError("Аллерген отсутствует в справочнике БД", "preferences.excluded_allergens")
        # Keep unrelated diets assigned by other clients.
        db.execute("DELETE FROM user_diets WHERE user_id=%s AND diet_id IN (SELECT id FROM diets WHERE kind='diet' AND name=ANY(%s))",
                   (uid, list(FOOD_DIETS.values()) + list(FLAG_DIETS.values())))
        for diet_id in selected:
            db.execute("INSERT INTO user_diets(user_id,diet_id) VALUES (%s,%s)", (uid, diet_id))
        db.execute("UPDATE users SET pevzner_diet_id=%s WHERE id=%s", (table_id, uid))
