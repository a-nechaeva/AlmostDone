import copy
import hashlib
import json
import os
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator, FormatChecker

from ..errors import APIError, invalid
from ..services.catalog import ExportValidation

PROJECT_ROOT = Path(__file__).resolve().parents[4]


class Contract:
    def __init__(self, path=None):
        path = path or os.environ.get("ALMOSTDONE_CONTRACT", PROJECT_ROOT / "docs/api/openapi.yaml")
        self.spec = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
        self.operations = {operation["operationId"]: (path, method, operation)
                           for path, methods in self.spec["paths"].items()
                           for method, operation in methods.items()}
        # A Contract is loaded once. Compile the catalogue schema and its version
        # once too; a new Contract carries a new binding when the schema changes.
        schema = self.operations['catalog_export'][2]['responses']['200']['content']['application/json']['schema']
        root = copy.deepcopy({**schema, 'components': self.spec['components']})
        version = hashlib.sha256(json.dumps(root, sort_keys=True, allow_nan=False).encode()).hexdigest()
        self.catalog_validation = ExportValidation(
            version, lambda body: self._validate_root(root, body, response=True))

    def resolve(self, schema):
        if "$ref" not in schema:
            return schema
        value = self.spec
        for part in schema["$ref"][2:].split("/"):
            value = value[part.replace("~1", "/").replace("~0", "~")]
        return value

    def validate(self, schema, value, *, response=False):
        root = {**schema, "components": self.spec["components"]}
        self._validate_root(root, value, response=response)

    def _validate_root(self, root, value, *, response=False):
        errors = list(Draft202012Validator(root, format_checker=FormatChecker()).iter_errors(value))
        # JSON Schema's number type also accepts non-finite Python floats. JSON does not.
        try:
            json.dumps(value, allow_nan=False)
        except (TypeError, ValueError):
            if response:
                raise APIError(500, "internal_error", "Некорректный ответ сервера")
            raise invalid("Ожидаются конечные JSON-значения")
        if errors:
            if response:
                raise APIError(500, "internal_error", "Ответ сервера не соответствует контракту")
            details = [{"field": ".".join(map(str, e.absolute_path)),
                        "code": "invalid_value", "message": e.message} for e in errors[:20]]
            raise APIError(422, "validation_error", "Запрос не соответствует контракту", details=details)

    def body(self, operation_id, value, media="application/json"):
        operation = self.operations[operation_id][2]
        self.validate(operation["requestBody"]["content"][media]["schema"], value)

    def parameters(self, operation_id, request):
        values = {}
        for param in self.operations[operation_id][2].get("parameters", []):
            param = self.resolve(param)
            name, location = param["name"], param["in"]
            if location == "header":  # Precondition headers are checked after idempotency replay.
                continue
            source = request.path_params if location == "path" else request.query_params
            schema = param["schema"]
            value = (source.getlist(name) if location == "query" and schema.get("type") == "array" and name in source
                     else source.get(name))
            if value is None:
                if "default" in schema:
                    value = schema["default"]
                elif param.get("required"):
                    raise invalid("Отсутствует обязательный параметр", name)
                else:
                    continue
            if schema.get("type") == "integer":
                try:
                    value = int(value)
                except (TypeError, ValueError):
                    raise invalid("Ожидается целое число", name)
            self.validate(schema, value)
            values[name] = value
        return values

    def response(self, operation_id, status, body):
        response = self.operations[operation_id][2]["responses"].get(str(status))
        if response and "content" in response:
            schema = response["content"]["application/json"]["schema"]
            # Arbitrary bodies have no snapshot provenance: always validate them.
            self.validate(schema, body, response=True)

    def openapi(self):
        result = copy.deepcopy(self.spec)
        result["servers"] = [{"url": "/api/v1"}]
        result["info"]["description"] = "REST API приложения. Источник каталога, хранилище и провайдеры задаются конфигурацией сервера."
        return result
