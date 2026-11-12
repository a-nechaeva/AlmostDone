"""Create the real HTTP application with explicit test-only storage."""
from almostdone_server.main import create_app as create_server_app

from .memory import Store


def create_app(**kwargs):
    if kwargs.get("store") is None:
        kwargs["store"] = Store()
    return create_server_app(**kwargs)
