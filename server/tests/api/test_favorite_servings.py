from fastapi.testclient import TestClient

from ..support.application import create_app
from ..support.http import auth, check, mutation
from ..support.catalog import custom_catalog


def test_favorites_scale_recipes_to_default_portions():
    data = custom_catalog()
    data['recipes'][0]['servings'] = 20
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        assert client.put('/api/v1/me/favorites/recipes/rice_tomato', headers=mutation(client, headers)).status_code == 200
        page = check(app, client.get('/api/v1/me/favorites/recipes', headers=headers), 'FavoriteRecipePage')
        card, = page['items']
        assert card['id'] == 'rice_tomato'
        assert card['servings'] == 2
        assert card['availability']['status'] == 'missing'
        assert card['buy_cost'] is not None
