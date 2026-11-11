"""Application factory: configure dependencies and create the FastAPI application."""
import os
from pathlib import Path

from .adapters.engine import DishgraphGateway
from .services.catalog import Catalog
from .repositories.catalog import JsonCatalogRepository, SeedCatalogRepository, MemoryCatalogRepository, PostgresCatalogRepository
from .integrations.yandex import YandexProvider
from .api.contract import Contract, PROJECT_ROOT
from .api.app import create_http_app
from .services.application import ApplicationService
from .repositories.memory import Store


def create_app(*, store=None, catalog_data=None, contract_path=None,
               auth_providers=None, recognizer=None, rate_limiter=None, recognition_provider=None):
    contract = Contract(contract_path)
    if store is None:
        database_url = os.environ.get("ALMOSTDONE_DATABASE_URL")
        if database_url:
            from .repositories.postgres import PostgresStore
            store = PostgresStore(database_url)
        else:
            store = Store()
    catalog_path = Path(os.environ.get("ALMOSTDONE_CATALOG", PROJECT_ROOT / "server/data/demo_catalog.json"))
    if catalog_data is None:
        if store.mode == "postgresql" and "ALMOSTDONE_CATALOG" not in os.environ:
            catalog_repository = PostgresCatalogRepository(store)
        elif catalog_path.suffix == ".sql":
            # pg_dump of the database (db/seed.sql): the real catalogue without PostgreSQL
            catalog_repository = SeedCatalogRepository(catalog_path)
        else:
            catalog_repository = JsonCatalogRepository(catalog_path)
    else:
        catalog_repository = MemoryCatalogRepository(catalog_data)
    engine = DishgraphGateway()
    catalog = Catalog(catalog_repository, engine)
    if recognizer is None:
        if recognition_provider is not None:
            from .adapters.recognition import EngineRecognizer
            recognizer = EngineRecognizer(engine, recognition_provider)
        elif os.environ.get("GIGACHAT_CREDENTIALS") and os.environ.get("GIGACHAT_MODEL"):
            from dishgraph.recognition import GigaChatProvider
            from .adapters.recognition import EngineRecognizer
            recognizer = EngineRecognizer(engine, GigaChatProvider(timeout=30))
    if auth_providers is None:
        client_id = os.environ.get("ALMOSTDONE_YANDEX_CLIENT_ID")
        auth_providers = {"yandex": YandexProvider(client_id)} if client_id else {}

    def validate_recognition_line(item):
        contract.validate({"$ref": "#/components/schemas/RecognitionLine"}, item, response=True)

    service = ApplicationService(store, catalog, auth_providers, recognizer, validate_recognition_line)

    return create_http_app(contract, service, rate_limiter)
