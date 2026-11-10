"""Fresh catalogue data and dependency wiring shared by server tests."""
import json
from .paths import SERVER_ROOT
from almostdone_server.adapters.engine import DishgraphGateway
from almostdone_server.repositories.catalog import MemoryCatalogRepository
from almostdone_server.services.catalog import Catalog


def make_catalog(data):
    return Catalog(MemoryCatalogRepository(data), DishgraphGateway())


def custom_catalog():
    return json.loads((SERVER_ROOT / 'data/demo_catalog.json').read_text(encoding='utf-8'))
