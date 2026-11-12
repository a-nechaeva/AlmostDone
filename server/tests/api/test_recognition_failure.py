from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from ..support.application import create_app
from almostdone_server.services.ports import RecognitionFailure
from ..support.http import auth, check, mutation, png


def test_failed_recognition_is_a_persisted_result_and_cannot_be_imported():
    class Recognizer:
        calls = 0
        def recognize(self, image, kind):
            self.calls += 1
            raise RecognitionFailure()

    recognizer = Recognizer()
    app = create_app(recognizer=recognizer)
    with TestClient(app) as client:
        headers = auth(app)
        command_headers = {**headers, "Idempotency-Key": str(uuid4())}
        response = client.post("/api/v1/recognitions", data={"kind": "products"}, files={"file": ("image.png", png(), "image/png")}, headers=command_headers)
        result = check(app, response, "Recognition", 202)
        assert result["status"] == "failed" and result["items"] == []
        assert result["failure"]["error"]["code"] == "recognition_failed"
        assert client.get(response.headers["location"], headers=headers).json() == result
        repeated = client.post("/api/v1/recognitions", data={"kind": "products"}, files={"file": ("image.png", png(), "image/png")}, headers=command_headers)
        assert repeated.json() == result and recognizer.calls == 1
        body = {"recognition_id": result["id"], "kind": "products", "items": [{"line_id": "line-1", "ingredient_id": "rice", "quantity": None}]}
        assert client.post("/api/v1/recognition-imports", json=body, headers=mutation(client, headers)).status_code == 422
        assert client.get("/api/v1/me/pantry", headers=headers).json()["items"] == []


@pytest.mark.parametrize("invalid", [None, {}, [{"private_response": "do-not-expose"}]])
def test_invalid_recognizer_output_returns_503_without_provider_details(invalid):
    class Recognizer:
        def recognize(self, image, kind):
            return invalid
    app = create_app(recognizer=Recognizer())
    with TestClient(app) as client:
        response = client.post("/api/v1/recognitions", data={"kind": "products"}, files={"file": ("image.png", png(), "image/png")},
                               headers={**auth(app), "Idempotency-Key": str(uuid4())})
        check(app, response, "Error", 503)
        assert "do-not-expose" not in response.text
