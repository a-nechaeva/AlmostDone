import json
from uuid import uuid4
from unittest.mock import Mock

from fastapi.testclient import TestClient

from dishgraph.recognition import RecognitionError
from dishgraph.recognition.providers import VisionProvider
from ..support.application import create_app
from ..support.http import auth, check, mutation, png


def upload(client, headers, kind):
    return client.post("/api/v1/recognitions", data={"kind": kind}, files={"file": ("image.png", png(), "image/png")},
                       headers={**headers, "Idempotency-Key": str(uuid4())})


def test_team_receipt_recognizer_is_connected_and_requires_confirmed_import():
    answer = {"items": [{"raw_name": "Рис", "candidates": [{"code": "rice", "confidence": 1}],
                         "quantity": {"value": 500, "unit": "g"}}]}
    provider = Mock(spec=VisionProvider)
    provider.complete.return_value = json.dumps(answer, ensure_ascii=False)
    app = create_app(recognition_provider=provider)
    with TestClient(app) as client:
        headers = auth(app)
        result = check(app, upload(client, headers, "receipt"), "Recognition", 202)
        assert result["status"] == "succeeded" and len(result["items"]) == 1
        line = result["items"][0]
        assert line["candidates"][0]["ingredient_id"] == "rice"
        assert line["suggested_quantity"] == {"value": 500, "unit": "g"}
        assert client.get("/api/v1/me/pantry", headers=headers).json()["items"] == []
        body = {"recognition_id": result["id"], "kind": "receipt", "items": [{"line_id": line["line_id"],
                "ingredient_id": "rice", "quantity": line["suggested_quantity"]}]}
        imported = check(app, client.post("/api/v1/recognition-imports", json=body, headers=mutation(client, headers)), "ImportResult")
        assert imported["pantry"][0]["ingredient_id"] == "rice"
        provider.complete.assert_called_once()
        provider.complete_text.assert_not_called()


def test_team_product_recognizer_preserves_unknown_weight():
    provider = Mock(spec=VisionProvider)
    provider.complete.return_value = json.dumps(
        {"items": [{"name": "Рис", "confidence": 1, "count": 1, "quantity": None}]}, ensure_ascii=False)
    provider.complete_text.return_value = json.dumps(
        {"matches": [{"index": 0, "candidates": [{"code": "rice", "confidence": 1}]}]})
    app = create_app(recognition_provider=provider)
    with TestClient(app) as client:
        result = check(app, upload(client, auth(app), "products"), "Recognition", 202)
        assert result["items"][0]["candidates"][0]["ingredient_id"] == "rice"
        assert result["items"][0]["suggested_quantity"] is None
        provider.complete.assert_called_once()
        provider.complete_text.assert_called_once()


def test_invalid_model_output_becomes_failed_job():
    provider = Mock(spec=VisionProvider)
    provider.complete.return_value = "not JSON"
    app = create_app(recognition_provider=provider)
    with TestClient(app) as client:
        result = check(app, upload(client, auth(app), "receipt"), "Recognition", 202)
        assert result["status"] == "failed" and result["failure"]["error"]["code"] == "recognition_failed"


def test_team_provider_outage_is_503_without_secret_error_text():
    provider = Mock(spec=VisionProvider)
    provider.complete.side_effect = RecognitionError("private-provider-key")
    app = create_app(recognition_provider=provider)
    with TestClient(app) as client:
        response = upload(client, auth(app), "receipt")
        check(app, response, "Error", 503)
        assert "private-provider-key" not in response.text
