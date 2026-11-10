"""Thin contract-driven REST routes: parse, invoke, serialize."""
import json

from fastapi import APIRouter, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse, Response

from ..errors import invalid
from .bodies import image_body
from .controller import Controller


async def read_body(request, contract, operation_id):
    if "requestBody" not in contract.operations[operation_id][2]:
        return {}
    if operation_id == "recognitions_create":
        return await image_body(request, contract, operation_id)
    if request.headers.get("content-type", "").split(";")[0].strip().lower() != "application/json":
        raise invalid("Требуется application/json")
    chunks, size = [], 0
    async for chunk in request.stream():
        size += len(chunk)
        if size > 1024 * 1024:
            raise invalid("JSON-запрос слишком большой")
        chunks.append(chunk)
    try:
        body = json.loads(b"".join(chunks))
    except (ValueError, UnicodeDecodeError):
        raise invalid("Некорректный JSON") from None
    contract.body(operation_id, body)
    return body


def create_router(contract, service):
    router = APIRouter(prefix="/api/v1")
    controller = Controller(contract, service)

    def endpoint(operation_id):
        async def handle(request: Request):
            parameters = contract.parameters(operation_id, request)
            body = await read_body(request, contract, operation_id)
            status, data, headers = await run_in_threadpool(
                controller.handle, operation_id, body, parameters, dict(request.headers))
            if status == 204:
                return Response(status_code=status, headers=headers)
            return JSONResponse(data, status_code=status, headers=headers)
        return handle

    for operation_id, (path, method, _) in contract.operations.items():
        router.add_api_route(path, endpoint(operation_id), methods=[method.upper()],
                             operation_id=operation_id, name=operation_id, include_in_schema=False)
    return router
