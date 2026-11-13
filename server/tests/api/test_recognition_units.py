"""Количество с фото переводится в единицу ингредиента из каталога."""
from uuid import uuid4
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from almostdone_server.services.ports import Recognizer

from ..support.application import create_app
from ..support.catalog import custom_catalog
from ..support.http import auth, check, png


@pytest.mark.parametrize("seen, shown", [
    ({"value": 2, "unit": "pcs"}, {"value": 240.0, "unit": "g"}),  # вес штуки известен
    ({"value": 300, "unit": "g"}, {"value": 300.0, "unit": "g"}),
    ({"value": 1000, "unit": "ml"}, None),  # плотности нет — количество не придумываем
])
def test_suggested_quantity_uses_catalog_unit(seen, shown):
    data = custom_catalog()
    tomato = next(i for i in data["ingredients"] if i["code"] == "tomato")
    tomato["grams_per_piece"] = 120

    recognizer = Mock(spec=Recognizer)
    recognizer.recognize.return_value = [
        {"line_id": "line-1", "raw_name": "ТОМАТЫ", "status": "matched", "suggested_quantity": seen,
         "candidates": [{"ingredient_id": "rice", "name": "Рис", "confidence": 0.2},
                        {"ingredient_id": "tomato", "name": "Томаты", "confidence": 0.9}]},
    ]
    app = create_app(catalog_data=data, recognizer=recognizer)
    with TestClient(app) as client:
        response = client.post("/api/v1/recognitions", data={"kind": "receipt"},
                               files={"file": ("receipt.png", png(), "image/png")},
                               headers={**auth(app), "Idempotency-Key": str(uuid4())})
        body = check(app, response, "Recognition", 202)
    assert body["items"][0]["suggested_quantity"] == shown
    recognizer.recognize.assert_called_once_with(png(), "receipt")
