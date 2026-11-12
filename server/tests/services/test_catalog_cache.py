import copy
from concurrent.futures import ThreadPoolExecutor

import pytest

from almostdone_server.adapters.engine import DishgraphGateway
from almostdone_server.services.catalog_cache import CatalogCache
from ..support.catalog import custom_catalog


class Repository:
    def __init__(self):
        self.data = custom_catalog()
        self.marker = 0
        self.loads = 0

    def revision(self):
        return self.marker

    def load_versioned(self):
        self.loads += 1
        return copy.deepcopy(self.data), self.marker

    def change(self, name):
        self.data['ingredients'][0]['name'] = name
        self.marker += 1


def catalog_cache(repository, validate=lambda candidate: candidate.export()):
    return CatalogCache(repository, DishgraphGateway, validate)


def test_unchanged_revision_does_not_reload_and_new_snapshot_replaces_engine():
    repo = Repository()
    live = catalog_cache(repo)
    gateway, version = live.gateway, live.version
    assert not live.refresh()
    assert repo.loads == 1
    repo.change('New ingredient name')
    assert live.refresh()
    assert repo.loads == 2
    assert live.gateway is not gateway
    assert live.version != version
    assert live.ingredients[repo.data['ingredients'][0]['code']]['name'] == 'New ingredient name'
    assert not live.refresh()
    assert repo.loads == 2


def test_request_keeps_its_snapshot_while_other_thread_publishes_new_one():
    repo = Repository()
    live = catalog_cache(repo)
    old_version, old_gateway = live.version, live.gateway
    with live.pin():
        repo.change('New name')
        with ThreadPoolExecutor(max_workers=1) as pool:
            assert pool.submit(live.refresh).result(timeout=5)
        assert live.version == old_version
        assert live.gateway is old_gateway
        with live.pin():
            assert live.version == old_version
    assert live.version != old_version
    assert live.gateway is not old_gateway


def test_failed_reload_keeps_previous_data_and_retries_same_revision():
    repo = Repository()
    rejected = []

    def validate(candidate):
        if rejected:
            raise ValueError('Invalid new catalogue')
        candidate.export()

    live = catalog_cache(repo, validate)
    old = live.export()
    old_gateway = live.gateway
    repo.change('Replacement ingredient')
    rejected.append(True)
    with pytest.raises(ValueError):
        live.refresh()
    assert live.export() == old
    assert live.gateway is old_gateway
    rejected.clear()
    assert live.refresh()
    assert live.export() != old


def test_commit_during_reload_is_not_lost():
    repo = Repository()
    live = catalog_cache(repo)
    repo.change('First change')
    original = repo.load_versioned

    def load():
        result = original()
        repo.change('Second change')
        repo.load_versioned = original
        return result

    repo.load_versioned = load
    assert live.refresh()
    code = repo.data['ingredients'][0]['code']
    assert live.ingredients[code]['name'] == 'First change'
    assert live.refresh()
    assert live.ingredients[code]['name'] == 'Second change'


