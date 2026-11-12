"""Каталог для подбора на устройстве и фото рецептов через сервер."""
from uuid import uuid4
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
from fastapi.testclient import TestClient

from almostdone_server.integrations import photos
from ..support.application import create_app
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


def test_concurrent_photo_requests_publish_a_complete_cache(app, monkeypatch, tmp_path):
    image = png()
    downloading = Barrier(2)
    publishing = Barrier(2)
    replace = photos.Path.replace

    def download(url):
        downloading.wait(timeout=10)
        return image

    def publish(path, target):
        publishing.wait(timeout=10)
        return replace(path, target)

    monkeypatch.setattr(photos, "download", download)
    monkeypatch.setattr(photos, "CACHE_DIR", tmp_path)
    with TestClient(app) as client:
        with monkeypatch.context() as concurrent:
            concurrent.setattr(photos.Path, "replace", publish)
            with ThreadPoolExecutor(max_workers=2) as pool:
                responses = list(pool.map(
                    lambda _: client.get("/api/v1/recipes/rice_tomato/photo"), range(2)))
        assert all(response.status_code == 200 and response.content == image for response in responses)
        # The next request must read the published file without downloading.
        assert client.get("/api/v1/recipes/rice_tomato/photo").content == image
    assert len(list(tmp_path.iterdir())) == 1


@pytest.mark.parametrize("optional_complete", [True, False])
def test_catalog_preserves_optional_allergens_and_completeness(optional_complete):
    data = custom_catalog()
    for ingredient in data["ingredients"]:
        ingredient["allergen_data_complete"] = True
        if ingredient["code"] == "cheese":
            ingredient["allergen_data_complete"] = optional_complete
    data["recipes"][0]["items"].append({"code": "cheese", "qty_g": None, "is_optional": True})
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        exported = check(app, client.get("/api/v1/catalog", headers=headers), "AppCatalog")
        detail = check(app, client.get("/api/v1/recipes/rice_tomato", headers=headers), "RecipeDetail")
    recipe = next(item for item in exported["recipes"] if item["id"] == "rice_tomato")
    assert recipe["allergens"] == detail["recipe"]["allergens"]["contains"] == ["milk"]
    assert recipe["allergen_data_complete"] is optional_complete
    assert (detail["recipe"]["allergens"]["completeness"] == "complete") is optional_complete
    assert "cheese" not in {item["ingredient_id"] for item in recipe["ingredients"]}


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


@pytest.mark.parametrize("missing_field", ["qty_g", "package_price"])
def test_partial_recipe_keeps_detail_and_photo_without_blocking_catalog(missing_field, downloads):
    data = custom_catalog()
    data["recipes"][0]["image_url"] = PHOTO
    if missing_field == "qty_g":
        data["recipes"][0]["items"][0]["qty_g"] = None
    else:
        data["ingredients"][0]["package_price"] = None
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        exported = check(app, client.get("/api/v1/catalog", headers=headers), "AppCatalog")
        assert [recipe["id"] for recipe in exported["recipes"]] == ["tomato_cheese"]
        detail = check(app, client.get("/api/v1/recipes/rice_tomato", headers=headers), "RecipeDetail")
        assert detail["recipe"]["availability"]["status"] == "unknown"
        assert detail["recipe"]["buy_cost"] is None
        assert detail["shopping_items"] == []
        response = client.get("/api/v1/recipes/rice_tomato/photo")
        assert response.status_code == 200 and response.content == png()
        request = {"request_id": str(uuid4()), "filters": FILTERS, "visibility": "visible", "limit": 20, "servings": 2}
        page = check(app, client.post("/api/v1/recommendations", json=request, headers=headers), "RecommendationPage", 201)
        assert {recipe["id"] for recipe in page["items"]} == {"rice_tomato", "tomato_cheese"}
    assert downloads == [PHOTO]
