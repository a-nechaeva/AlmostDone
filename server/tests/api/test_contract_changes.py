import copy
from uuid import uuid4

from fastapi.testclient import TestClient

from almostdone_server.main import create_app
from ..support.http import FILTERS, auth, check, mutation
from ..support.catalog import custom_catalog


def test_profile_dictionary_binds_every_supported_field():
    app = create_app()
    with TestClient(app) as client:
        headers = auth(app)
        options = check(app, client.get('/api/v1/dietary-options', headers=headers), 'DietaryOptions')
        fields = {o['profile_binding']['field'] for o in options['items']}
        assert fields == {'food_type', 'gluten_free', 'lactose_free', 'diabetes', 'diet_table_id'}
        assert {o['profile_binding']['value'] for o in options['items'] if o['profile_binding']['field'] == 'food_type'} == {'any', 'vegetarian', 'vegan'}


def test_repeated_allergen_query_preserves_hidden_recipe_context():
    data = custom_catalog()
    for ingredient in data['ingredients']:
        ingredient['allergen_data_complete'] = True
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        body = {'request_id': str(uuid4()), 'servings': 2, 'filters': {**FILTERS, 'exclude_allergens': ['milk', 'eggs']}, 'visibility': 'hidden', 'limit': 20}
        page = check(app, client.post('/api/v1/recommendations', json=body, headers=headers), 'RecommendationPage', 201)
        card = page['items'][0]
        assert card['suitability']['status'] == 'hidden'
        reason, = card['suitability']['reasons']
        assert reason['code'] == 'excluded_allergen'
        assert reason['ingredient_ids'] == ['cheese']
        assert reason['restriction_ids'] == ['milk']
        detail = check(app, client.get('/api/v1/recipes/' + card['id'], params=[('servings', 2), ('exclude_allergens', 'milk'), ('exclude_allergens', 'eggs')], headers=headers), 'RecipeDetail')
        assert detail['recipe'] == card
        assert client.get('/api/v1/recipes/' + card['id'], params={'exclude_allergens': 'unknown'}, headers=headers).status_code == 422


def test_single_purchase_returns_multiple_options_and_multiple_packages():
    data = custom_catalog()
    data['recipes'][0]['items'][0]['qty_g'] = 1200
    data['recipes'][1]['items'][1]['qty_g'] = 600
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        client.post('/api/v1/me/pantry/add', json={'ingredient_id': 'tomato', 'quantity': {'value': 2000, 'unit': 'g'}}, headers=mutation(client, headers))
        body = {'request_id': str(uuid4()), 'servings': 2, 'filters': FILTERS, 'budget': {'minor_units': 200000, 'currency': 'RUB'}}
        response = check(app, client.post('/api/v1/recommendations/single-purchase', json=body, headers=headers), 'SinglePurchaseResult')
        assert len(response['options']) == 2
        assert all(option['shopping_item']['package_count'] == 3 for option in response['options'])
        assert response['servings'] == 2
        assert response['options'][0]['shopping_item']['ingredient_id'] == 'rice'


def test_graph_that_requires_package_repair_is_explicitly_unsupported():
    data = custom_catalog()
    template = data['recipes'][0]
    data['recipes'] = [
        {**copy.deepcopy(template), 'id': 'large', 'items': [{'code': 'rice', 'qty_g': 2500}]},
        {**copy.deepcopy(template), 'id': 'small', 'items': [{'code': 'rice', 'qty_g': 100}, {'code': 'tomato', 'qty_g': 100}]},
    ]
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        body = {'request_id': str(uuid4()), 'servings': 2, 'filters': FILTERS, 'visibility': 'visible', 'limit': 1}
        page = check(app, client.post('/api/v1/recommendations', json=body, headers=headers), 'RecommendationPage', 201)
        result = check(app, client.get('/api/v1/recommendations/' + page['snapshot_id'] + '/graph', headers=headers), 'Error', 503)
        assert result['error']['details'][0]['field'] == 'graph_package_transitions'


def test_optional_allergen_warning_is_not_reimplemented_in_server():
    data = custom_catalog()
    for ingredient in data['ingredients']:
        ingredient['allergen_data_complete'] = True
    data['recipes'][0]['items'].append({'code': 'cheese', 'qty_g': 20, 'is_optional': True})
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        result = check(app, client.get('/api/v1/recipes/rice_tomato', params={'exclude_allergens': 'milk'}, headers=auth(app)), 'Error', 503)
        assert result['error']['details'][0]['field'] == 'optional_allergen_warnings'


def test_false_equipment_flags_do_not_invent_no_cook():
    data = custom_catalog()
    data['recipes'][1].pop('no_cook')
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        detail = check(app, client.get('/api/v1/recipes/tomato_cheese', headers=auth(app)), 'RecipeDetail')
        assert detail['recipe']['methods'] == []
