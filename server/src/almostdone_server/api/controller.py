"""Translate HTTP metadata to application commands and present their results."""
import re
from uuid import UUID

from ..errors import invalid
from ..services.commands import Command


class Controller:
    def __init__(self, contract, service):
        self.contract, self.service = contract, service

    def handle(self, operation_id, body, parameters, headers):
        _, _, operation = self.contract.operations[operation_id]
        names = {self.contract.resolve(p)["name"] for p in operation.get("parameters", [])}
        key = None
        if "Idempotency-Key" in names:
            try:
                key = str(UUID(headers.get("idempotency-key", "")))
            except (ValueError, AttributeError):
                raise invalid("Требуется UUID Idempotency-Key", "Idempotency-Key") from None
        version = None
        if headers.get("if-match"):
            value = headers["if-match"]
            match = re.fullmatch(r'"state-(0|[1-9]\d*)"', value) if len(value) < 64 else None
            version = int(match[1]) if match else -1
        scheme, _, token = headers.get("authorization", "").partition(" ")
        command = Command(
            operation_id, body, parameters, token if scheme.lower() == "bearer" else "",
            expected_version=version, idempotency_key=key,
        )
        status = next(int(code) for code in operation["responses"] if str(code).startswith("2"))
        result = self.service.execute(command, lambda result: self.contract.response(operation_id, status, result.data))
        response_headers = {}
        if operation_id not in ("health_get", "readiness_get"):
            response_headers = {"Cache-Control": "no-store", "X-Storage-Mode": self.service.store.mode,
                                "X-Catalog-Mode": "demo" if self.service.catalog.demo else "configured"}
            if result.version is not None:
                response_headers["ETag"] = f'"state-{result.version}"'
        if operation_id in ("health_get", "readiness_get"):
            response_headers['Cache-Control'] = 'no-store'
        if operation_id == "recognitions_create":
            response_headers.update(Location="/api/v1/recognitions/" + result.data["id"], **{"Retry-After": "2"})
        return status, result.data, response_headers
