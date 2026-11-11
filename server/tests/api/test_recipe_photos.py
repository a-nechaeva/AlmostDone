"""Каталог для подбора на устройстве и фото рецептов через сервер."""
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from almostdone_server.integrations import photos
from almostdone_server.main import create_app
from ..support.catalog import custom_catalog
from ..support.http import FILTERS, auth, check, png

PHOTO = "https://photos.example/rice.png"


@pytest.fixture
def app():
    data = custom_catalog()
    data["recipes"][0]["image_url"] = PHOTO
    return create_app(catalog_data=data)


@pytest.fixture
def downloads(monkeypatch, tmp_path):
    calls = []

    def download(url):
        calls.append(url)
        return png()

    monkeypatch.setattr(photos, "download", download)
    monkeypatch.setattr(photos, "CACHE_DIR", tmp_path)
    return calls


def test_catalog_lists_engine_recipes_with_proxied_photo(app):
    with TestClient(app) as client:
        result = check(app, client.get("/api/v1/catalog", headers=auth(app)), "AppCatalog")
    recipes = {r["id"]: r for r in result["recipes"]}
    assert recipes["rice_tomato"]["photo_url"] == "http://testserver/api/v1/recipes/rice_tomato/photo"
    assert recipes["tomato_cheese"]["photo_url"] is None
    known = {i["id"] for i in result["ingredients"]}
    assert all(item["ingredient_id"] in known and item["quantity"]["value"] > 0
               for recipe in result["recipes"] for item in recipe["ingredients"])


def test_catalog_requires_session(app):
    with TestClient(app) as client:
        assert client.get("/api/v1/catalog").status_code == 401


def test_photo_is_downloaded_once_and_served_without_session(app, downloads):
    with TestClient(app) as client:
        first = client.get("/api/v1/recipes/rice_tomato/photo")
        second = client.get("/api/v1/recipes/rice_tomato/photo")
    assert first.status_code == second.status_code == 200
    assert first.headers["content-type"] == "image/png"
    assert first.content == png()
    assert downloads == [PHOTO]


def test_photo_errors(app, monkeypatch, tmp_path):
    def broken(url):
        raise photos.PhotoUnavailable("timeout")

    monkeypatch.setattr(photos, "download", broken)
    monkeypatch.setattr(photos, "CACHE_DIR", tmp_path)
    with TestClient(app) as client:
        assert check(app, client.get("/api/v1/recipes/rice_tomato/photo"), "Error", 503)
        assert check(app, client.get("/api/v1/recipes/tomato_cheese/photo"), "Error", 404)
        assert check(app, client.get("/api/v1/recipes/unknown/photo"), "Error", 404)


def test_recipe_cards_point_photos_at_server(app):
    with TestClient(app) as client:
        headers = auth(app)
        body = {"request_id": str(uuid4()), "filters": FILTERS, "visibility": "visible", "limit": 20, "servings": 2}
        page = client.post("/api/v1/recommendations", json=body, headers=headers)
        detail = client.get("/api/v1/recipes/rice_tomato", headers=headers)
    expected = "http://testserver/api/v1/recipes/rice_tomato/photo"
    assert page.status_code == 201, page.text
    assert {item["id"]: item["photo_url"] for item in page.json()["items"]}["rice_tomato"] == expected
    assert detail.status_code == 200, detail.text
    assert detail.json()["recipe"]["photo_url"] == expected
