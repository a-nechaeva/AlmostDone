"""FastAPI lifecycle, middleware and error presentation."""
import asyncio
import logging
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from ..errors import (APIError, invalid, StorageError, StorageUnavailable,
                      StorageSchemaError, StorageConflict, StorageValueError)
from .rate_limit import RateLimiter
from .routes import create_router


def create_http_app(contract, service, rate_limiter=None):
    @asynccontextmanager
    async def lifespan(app):
        async def cleanup():
            while True:
                try:
                    await run_in_threadpool(service.purge)
                except (APIError, StorageError):
                    logging.getLogger(__name__).warning("Storage cleanup deferred; retrying in 60 seconds")
                await asyncio.sleep(60)

        worker = asyncio.create_task(cleanup())
        async def refresh_catalog():
            while True:
                try:
                    async with service.catalog.listen() as notifications:
                        # Subscribe first, then catch changes made before startup
                        # or while disconnected. No revision polling while idle.
                        await run_in_threadpool(service.catalog.refresh)
                        async for _ in notifications:
                            await run_in_threadpool(service.catalog.refresh)
                    raise ConnectionError('Catalogue notification stream ended')
                except Exception:
                    logging.getLogger(__name__).warning('Catalogue refresh failed; keeping previous snapshot')
                    await asyncio.sleep(5)

        refresher = (asyncio.create_task(refresh_catalog())
                     if callable(getattr(service.catalog, 'listen', None)) else None)
        try:
            yield
        finally:
            worker.cancel()
            with suppress(asyncio.CancelledError):
                await worker
            if refresher is not None:
                refresher.cancel()
                with suppress(asyncio.CancelledError):
                    await refresher

    app = FastAPI(title=contract.spec["info"]["title"], lifespan=lifespan)
    app.state.service = service
    app.state.contract = contract
    limiter = rate_limiter if rate_limiter is not None else RateLimiter()
    app.state.rate_limiter = limiter
    app.openapi = contract.openapi

    @app.middleware("http")
    async def limit_requests(request, call_next):
        if request.url.path.startswith("/api/v1/") and request.url.path not in (
            '/api/v1/health', '/api/v1/health/ready',
        ):
            # Use the actual peer, never an untrusted X-Forwarded-For header.
            peer = request.client.host if request.client else "unknown"
            try:
                limiter.check(peer, request.url.path)
            except APIError as error:
                return JSONResponse(error.body(), status_code=error.status,
                                    headers={"Cache-Control": "no-store", **error.headers})
        return await call_next(request)

    @app.exception_handler(APIError)
    async def api_error(request, error):
        authentication = {"WWW-Authenticate": "Bearer"} if error.status == 401 else {}
        return JSONResponse(error.body(), status_code=error.status,
                            headers={"Cache-Control": "no-store", **authentication, **error.headers})

    @app.exception_handler(RequestValidationError)
    async def request_error(request, error):
        return await api_error(request, invalid("Некорректный запрос"))

    @app.exception_handler(StorageError)
    async def storage_error(request, error):
        if isinstance(error, StorageValueError):
            presented = invalid(str(error), error.field)
        elif isinstance(error, StorageConflict):
            presented = APIError(409, "context_changed", str(error))
        elif isinstance(error, (StorageUnavailable, StorageSchemaError)):
            presented = APIError(503, "service_unavailable", str(error))
        else:
            presented = APIError(500, "internal_error", "Ошибка хранилища")
        return await api_error(request, presented)

    @app.exception_handler(HTTPException)
    async def http_error(request, error):
        return JSONResponse(APIError(error.status_code, "not_found" if error.status_code == 404 else "http_error",
                                     "Ресурс или метод недоступен").body(),
                            status_code=error.status_code, headers={"Cache-Control": "no-store"})

    @app.exception_handler(Exception)
    async def internal_error(request, error):
        # Do not echo payloads, SQL, tokens, provider errors or raw recognition data.
        return JSONResponse(APIError(500, "internal_error", "Внутренняя ошибка сервера").body(),
                            status_code=500, headers={"Cache-Control": "no-store"})

    app.include_router(create_router(contract, service))
    return app
