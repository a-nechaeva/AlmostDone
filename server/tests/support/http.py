"""HTTP test helpers; no test cases or fixture registration."""
import io
from uuid import uuid4
from PIL import Image


FILTERS = {"q": "", "mode": "all", "max_minutes": None, "max_kcal_per_serving": None,
           "equipment": ["stove", "oven", "microwave", "no_cook"], "exclude_allergens": []}


def session(app, user_id="alice"):
    service = app.state.service
    with service.store.transaction() as db:
        return service.auth.issue(db, user_id)


def auth(app, user_id="alice"):
    return {"Authorization": "Bearer " + session(app, user_id)["access_token"]}


def mutation(client, headers, *, key=None):
    state = client.get("/api/v1/me/state", headers=headers)
    assert state.status_code == 200
    return {**headers, "If-Match": state.headers["etag"], "Idempotency-Key": key or str(uuid4())}


def check(app, response, schema, status=200):
    assert response.status_code == status, response.text
    app.state.contract.validate({"$ref": "#/components/schemas/" + schema}, response.json(), response=True)
    return response.json()


def png():
    output = io.BytesIO()
    Image.new("RGB", (2, 2)).save(output, format="PNG")
    return output.getvalue()
