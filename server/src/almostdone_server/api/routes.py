"""Thin contract-driven REST routes: parse, invoke, serialize."""
import json
from urllib.parse import quote

from fastapi import APIRouter, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse, Response

from ..errors import APIError, invalid
from ..integrations import photos
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


def proxy_photo_urls(data, base_url):
    """Point recipe photo links at this server (GET /recipes/{id}/photo).

    The photo host is behind Cloudflare and is unreachable from some phone networks, while the
    server downloads it fine; only the HTTP layer knows the address the client used.
    """
    if isinstance(data, list):
        return [proxy_photo_urls(item, base_url) for item in data]
    if not isinstance(data, dict):
        return data
    result = {key: proxy_photo_urls(value, base_url) for key, value in data.items()}
    if isinstance(result.get("photo_url"), str) and isinstance(result.get("id"), str):
        result["photo_url"] = f"{base_url}api/v1/recipes/{quote(result['id'], safe='')}/photo"
    return result


async def recipe_photo(service, recipe_id):
    url = service.catalog.photo_source(recipe_id)
    if url is None:
        raise APIError(404, "not_found", "Фото рецепта не найдено")
    try:
        data, kind = await run_in_threadpool(photos.fetch, url)
    except photos.PhotoUnavailable:
        raise APIError(503, "service_unavailable", "Фото сейчас недоступно") from None
    return Response(data, media_type=kind, headers={"Cache-Control": "public, max-age=86400"})


def create_router(contract, service):
    router = APIRouter(prefix="/api/v1")
    controller = Controller(contract, service)

    def endpoint(operation_id):
        async def handle(request: Request):
            parameters = contract.parameters(operation_id, request)
            if operation_id == "recipes_photo":
                return await recipe_photo(service, parameters["recipe_id"])
            body = await read_body(request, contract, operation_id)
            status, data, headers = await run_in_threadpool(
                controller.handle, operation_id, body, parameters, dict(request.headers))
            if status == 204:
                return Response(status_code=status, headers=headers)
            return JSONResponse(proxy_photo_urls(data, str(request.base_url)), status_code=status, headers=headers)
        return handle

    for operation_id, (path, method, _) in contract.operations.items():
        router.add_api_route(path, endpoint(operation_id), methods=[method.upper()],
                             operation_id=operation_id, name=operation_id, include_in_schema=False)
    return router
