import json

import pytest
from jsonschema import Draft202012Validator

from almostdone_server.api.contract import Contract

from ..support.paths import PROJECT_ROOT
CASES = json.loads((PROJECT_ROOT / "docs/api/examples.json").read_text(encoding="utf-8"))["cases"]


@pytest.mark.parametrize("case", CASES, ids=[case["name"] for case in CASES])
def test_shared_contract_example(case):
    contract = Contract()
    contract.validate({"$ref": "#/components/schemas/" + case["schema"]}, case["body"], response=True)
    if "request_schema" in case:
        contract.validate({"$ref": "#/components/schemas/" + case["request_schema"]}, case["request"])


def test_all_contract_schemas_and_references_are_valid():
    contract = Contract()
    for schema in contract.spec["components"]["schemas"].values():
        Draft202012Validator.check_schema(schema)

    def walk(value):
        if isinstance(value, dict):
            if "$ref" in value:
                contract.resolve(value)
            for item in value.values():
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)
    walk(contract.spec)
