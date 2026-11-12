import copy
from uuid import uuid4

from fastapi.testclient import TestClient

from ..support.application import create_app
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


def test_single_purchase_keeps_affordable_recipes_when_other_recipes_are_too_expensive():
    data = custom_catalog()
    expensive = copy.deepcopy(data['recipes'][0])
    expensive['id'] = 'expensive_rice'
    expensive['items'][0]['qty_g'] = 2500
    data['recipes'].append(expensive)
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        client.post('/api/v1/me/pantry/add', json={'ingredient_id': 'tomato', 'quantity': {'value': 2000, 'unit': 'g'}}, headers=mutation(client, headers))
        body = {'request_id': str(uuid4()), 'servings': 2, 'filters': FILTERS,
                'budget': {'minor_units': 10000, 'currency': 'RUB'}}
        response = check(app, client.post('/api/v1/recommendations/single-purchase', json=body, headers=headers), 'SinglePurchaseResult')
        assert response['status'] == 'found'
        option, = response['options']
        assert option['shopping_item']['ingredient_id'] == 'rice'
        assert option['shopping_item']['package_count'] == 1
        assert option['shopping_item']['total_price']['minor_units'] == 10000
        assert option['unlocked_recipe_ids'] == ['rice_tomato']


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


def test_optional_allergen_warning_does_not_reject_or_hide_the_recipe():
    data = custom_catalog()
    for ingredient in data['ingredients']:
        ingredient['allergen_data_complete'] = True
    data['recipes'][0]['items'].append({'code': 'cheese', 'qty_g': 20, 'is_optional': True})
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        result = check(app, client.get('/api/v1/recipes/rice_tomato', params={'exclude_allergens': 'milk'}, headers=auth(app)), 'RecipeDetail')
        assert result['recipe']['suitability']['status'] == 'allowed'
        reason, = result['recipe']['suitability']['reasons']
        assert reason['code'] == 'skip_optional'
        assert reason['ingredient_ids'] == ['cheese']
        assert reason['restriction_ids'] == ['milk']
        assert result['recipe']['allergens']['contains'] == ['milk']


def test_false_equipment_flags_do_not_invent_no_cook():
    data = custom_catalog()
    data['recipes'][1].pop('no_cook')
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        detail = check(app, client.get('/api/v1/recipes/tomato_cheese', headers=auth(app)), 'RecipeDetail')
        assert detail['recipe']['methods'] == []


def test_catalog_export_carries_curated_dietary_facts():
    app = create_app()
    with TestClient(app) as client:
        exported = check(app, client.get('/api/v1/catalog', headers=auth(app)), 'AppCatalog')
    facts = {recipe['id']: recipe['dietary_facts'] for recipe in exported['recipes']}
    assert facts['rice_tomato'] == {'vegetarian': True, 'vegan': True,
                                    'gluten_free': True, 'lactose_free': True}
    assert facts['tomato_cheese'] == {'vegetarian': None, 'vegan': False,
                                      'gluten_free': None, 'lactose_free': False}


def test_catalog_export_computes_dietary_facts_from_ingredient_diet_data():
    data = custom_catalog()
    for recipe in data['recipes']:
        recipe.pop('dietary_facts')
    for ingredient in data['ingredients']:
        ingredient['diet_exclusions'] = ['lactose_free', 'vegan'] if ingredient['code'] == 'cheese' else []
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        exported = check(app, client.get('/api/v1/catalog', headers=auth(app)), 'AppCatalog')
    facts = {recipe['id']: recipe['dietary_facts'] for recipe in exported['recipes']}
    assert facts['rice_tomato'] == {'vegetarian': True, 'vegan': True,
                                    'gluten_free': True, 'lactose_free': True}
    assert facts['tomato_cheese'] == {'vegetarian': True, 'vegan': False,
                                      'gluten_free': True, 'lactose_free': False}


def test_catalog_export_marks_dietary_facts_unknown_without_diet_data():
    data = custom_catalog()
    for recipe in data['recipes']:
        recipe.pop('dietary_facts')
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        exported = check(app, client.get('/api/v1/catalog', headers=auth(app)), 'AppCatalog')
    assert all(recipe['dietary_facts'] == {'vegetarian': None, 'vegan': None,
                                           'gluten_free': None, 'lactose_free': None}
               for recipe in exported['recipes'])
