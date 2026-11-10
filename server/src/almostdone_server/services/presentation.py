"""Serialize the engine graph. Never construct or repair graph topology here."""
import hashlib

from .catalog import money, kopecks, unsupported


def graph(catalog, details, options):
    supported = [option for option in options if option.level <= 3]
    result = catalog.gateway.build_graph(supported)
    cards = {detail["recipe"]["id"]: detail["recipe"] for detail in details}
    identifiers = {node["id"]: node["id"] if node["id"] == "home" else
                   node["type"] + ":" + hashlib.sha256(node["id"].encode()).hexdigest()[:24]
                   for node in result["nodes"]}
    engine_nodes = {node["id"]: node for node in result["nodes"]}
    nodes, edges = [], []
    for node in result["nodes"]:
        base = {"id": identifiers[node["id"]], "level": node["level"]}
        if node["type"] == "home":
            nodes.append({**base, "kind": "home", "label": "Дома"})
        elif node["type"] == "purchase":
            nodes.append({**base, "kind": "purchase", "label": ", ".join(item["name"] for item in node["items"]),
                          "shopping_items": [catalog.shopping_item(item["code"], item["packs"], item["cost"]) for item in node["items"]],
                          "cost": money(kopecks(node["cost"])), "dish_count": node["dish_count"]})
        else:
            card = cards[node["recipe_id"]]
            nodes.append({**base, "kind": "recipe", "label": card["title"], "recipe_id": card["id"], "recipe": card})
    for edge in result["edges"]:
        base = {"source": identifiers[edge["from"]], "target": identifiers[edge["to"]]}
        target, source = engine_nodes[edge["to"]], engine_nodes[edge["from"]]
        if target["type"] == "dish":
            edges.append({**base, "kind": "unlocks"})
            continue
        # The REST schema requires exact package addition. Reject an incompatible
        # engine edge; do not invent a different parent or recalculate deltas.
        counts = {item["code"]: item["packs"] for item in source.get("items", [])}
        for item in edge.get("add", []):
            counts[item["code"]] = counts.get(item["code"], 0) + item["packs"]
        if counts != {item["code"]: item["packs"] for item in target["items"]}:
            raise unsupported("graph_package_transitions")
        edges.append({**base, "kind": "extends", "add_cost": money(kopecks(edge["add_cost"])),
                      "add": [catalog.shopping_item(item["code"], item["packs"], item["cost"]) for item in edge["add"]]})
    return {"scope": "snapshot", "nodes": nodes, "edges": edges,
            "unrepresented_recipe_ids": [option.recipe.id for option in options if option.level > 3]}
