"""Availability modes must preserve hidden recipes and uncertain suitability."""
from uuid import uuid4

import pytest

from ..support.http import FILTERS, auth, check, mutation


@pytest.mark.parametrize("mode", ["now", "buy_1_3"])
@pytest.mark.parametrize("restriction", ["milk", "diabetes"])
def test_ready_engine_filters_and_unsupported_restrictions(app, client, mode, restriction):
    headers = auth(app)
    for ingredient in app.state.service.catalog.ingredients.values():
        ingredient['allergen_data_complete'] = True
    if mode == 'now':
        for ingredient in ('rice', 'tomato', 'cheese'):
            client.post('/api/v1/me/pantry/add', headers=mutation(client, headers),
                        json={'ingredient_id': ingredient, 'quantity': {'value': 2000, 'unit': 'g'}})
    if restriction == 'diabetes':
        preferences = client.get('/api/v1/me', headers=headers).json()['preferences']
        preferences['diabetes'] = True
        client.patch('/api/v1/me', headers=mutation(client, headers), json={'preferences': preferences})
    request = {'request_id': str(uuid4()), 'servings': 2,
               'filters': {**FILTERS, 'mode': mode, 'exclude_allergens': ['milk'] if restriction == 'milk' else []},
               'visibility': 'hidden', 'limit': 20}
    response = client.post('/api/v1/recommendations', json=request, headers=headers)
    if restriction == 'diabetes':
        check(app, response, 'Error', 503)
    else:
        page = check(app, response, 'RecommendationPage', 201)
        assert [card['id'] for card in page['items']] == ['tomato_cheese']


def test_database_rule_change_invalidates_recommendation_snapshot(app, client, monkeypatch):
    headers = auth(app)
    decisions = {'rice_tomato': {'hidden': False, 'restrictions': [], 'skip_optional': []}}
    monkeypatch.setattr(app.state.service.store, 'dietary_visibility', lambda db, uid: decisions)
    request = {'request_id': str(uuid4()), 'servings': 2, 'filters': FILTERS,
               'visibility': 'visible', 'limit': 1}
    first = client.post('/api/v1/recommendations', json=request, headers=headers)
    assert first.status_code == 201, first.text
    snapshot = first.json()
    state = client.get('/api/v1/me/state', headers=headers).json()
    decisions['rice_tomato']['hidden'] = True
    response = client.get('/api/v1/recommendations/' + snapshot['snapshot_id'],
                          params={'cursor': snapshot['page']['next_cursor']}, headers=headers)
    assert response.status_code == 409, response.text
    assert client.get('/api/v1/me/state', headers=headers).json() == state
