from collections import deque

from dishgraph import build_graph, load_catalog, reachable_dishes
from dishgraph.demo import DEMO_PANTRY


def edges_by_src(graph):
    out = {}
    for e in graph["edges"]:
        out.setdefault(e["from"], []).append(e)
    return out


def assert_valid(graph):
    ids = [n["id"] for n in graph["nodes"]]
    assert len(ids) == len(set(ids)), "id узлов должны быть уникальны"
    ids = set(ids)
    for e in graph["edges"]:
        assert e["from"] in ids and e["to"] in ids, f"висящее ребро {e}"

    # Каждый узел достижим из home
    seen, queue, out = {"home"}, deque(["home"]), edges_by_src(graph)
    while queue:
        for e in out.get(queue.popleft(), []):
            if e["to"] not in seen:
                seen.add(e["to"])
                queue.append(e["to"])
    assert seen == ids


def test_chain_of_purchases(catalog):
    graph = build_graph(reachable_dishes({"egg"}, catalog), catalog)
    assert_valid(graph)
    out = edges_by_src(graph)

    assert {e["to"] for e in out["home"]} == {"dish:herb_egg", "buy:milk"}
    assert {e["to"] for e in out["buy:milk"]} == {"dish:omelette", "dish:milk_drink", "buy:flour+milk"}
    step = next(e for e in out["buy:milk"] if e["to"] == "buy:flour+milk")
    assert step["add"] == [{"code": "flour", "name": "Flour", "packs": 1, "cost": 60.0}]
    assert step["add_cost"] == 60
    assert {e["to"] for e in out["buy:flour+milk"]} == {"dish:pancakes", "buy:cheese+flour+milk"}


def test_purchase_node_has_two_parents(catalog):
    graph = build_graph(reachable_dishes(set(), catalog), catalog)
    assert_valid(graph)
    parents = {e["from"] for e in graph["edges"] if e["to"] == "buy:egg+milk"}
    assert parents == {"buy:egg", "buy:milk"}


def test_purchase_node_fields(catalog):
    graph = build_graph(reachable_dishes({"egg"}, catalog), catalog)
    node = next(n for n in graph["nodes"] if n["id"] == "buy:milk")
    assert node == {
        "id": "buy:milk",
        "type": "purchase",
        "level": 1,
        "items": [{"code": "milk", "name": "Milk", "packs": 1, "cost": 80.0}],
        "cost": 80,
        "dish_count": 2,
    }


def test_purchase_node_with_partial_quantity(catalog):
    graph = build_graph(reachable_dishes({"egg": None, "milk": 150}, catalog), catalog)
    node = next(n for n in graph["nodes"] if n["id"] == "buy:milk")
    # молока 150 г: омлету (100 г) хватает, напитку (200 г) не хватает 50 г — одна упаковка
    assert node["items"] == [{"code": "milk", "name": "Milk", "packs": 1, "cost": 80.0}]
    assert node["dish_count"] == 1


def test_fixtures_graph_is_valid():
    catalog = load_catalog()
    for pantry in (set(), DEMO_PANTRY, set(catalog.ingredients)):
        assert_valid(build_graph(reachable_dishes(pantry, catalog), catalog))
