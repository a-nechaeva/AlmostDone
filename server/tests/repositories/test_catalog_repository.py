import json

from almostdone_server.repositories.catalog import JsonCatalogRepository, MemoryCatalogRepository
from almostdone_server.services.catalog import Catalog


class RecordingGateway:
    def configure(self, data):
        self.data = data

    def search(self, query):
        return [code for code in (i['code'] for i in self.data['ingredients']) if code == query]


def test_service_loads_repository_records_before_calling_engine(tmp_path):
    path = tmp_path / 'catalog.json'
    data = {'source_name': 'Repository', 'ingredients': [{'code': 'rice', 'name': 'Rice'}], 'recipes': []}
    path.write_text(json.dumps(data), encoding='utf-8')
    gateway = RecordingGateway()
    catalog = Catalog(JsonCatalogRepository(path), gateway)
    assert catalog.ingredient('rice')['name'] == 'Rice'
    assert catalog.source['name'] == 'Repository'
    assert gateway.data == data
    assert catalog.search('rice') == ['rice']


def test_supplied_catalog_repository_owns_its_records():
    data = {'ingredients': [{'code': 'rice', 'name': 'Rice'}], 'recipes': []}
    repository = MemoryCatalogRepository(data)
    data['ingredients'].clear()
    first = repository.load()
    first['ingredients'].clear()
    assert repository.load()['ingredients'] == [{'code': 'rice', 'name': 'Rice'}]
