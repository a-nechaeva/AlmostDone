from fastapi.testclient import TestClient

from almostdone_server.main import create_app
from ..support.http import auth, check, mutation
from ..support.catalog import custom_catalog


def test_favorites_keep_recipes_without_supported_default_portion_scaling():
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
        assert card['availability']['status'] == 'unknown'
        assert card['buy_cost'] is None
