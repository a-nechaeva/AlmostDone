"""Сервер «Почти готово» — FastAPI поверх движка dishgraph.

Пути и форматы — из контракта docs/api/openapi.yaml (префикс /api/v1). Демо-упрощения этой версии:
  * без авторизации: один пользователь «demo», заголовок Authorization не проверяется;
  * кладовка, снимки подбора и распознавания — в памяти процесса;
  * If-Match и Idempotency-Key принимаются, но не обязательны;
  * снимок подбора отдаётся страницами по limit, граф — по всему снимку;
  * распознавание синхронное: POST /recognitions сразу отвечает status=succeeded или failed.

Запуск (из папки backend): uvicorn --factory app.main:create_app --reload
Документация API — http://localhost:8000/docs
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from typing import Any, Literal

from fastapi import APIRouter, Depends, FastAPI, File, Form, Query, Request, Response, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.exceptions import HTTPException as StarletteHTTPException

from dishgraph import (
    SearchIndex,
    best_purchases,
    best_single_purchases,
    build_graph,
    dish_option,
    reachable_dishes,
)
from dishgraph.recognition import MAX_IMAGE_BYTES, InvalidImage, RecognitionError, VisionProvider, recognize

from . import catalog_source, contract
from .config import Settings
from .state import DEMO_USER_ID, RECOGNITION_TTL, SNAPSHOT_TTL, DemoState, RecognitionJob, Snapshot, iso, new_id, now

API_PREFIX = "/api/v1"


# --- ошибки в формате контракта ------------------------------------------------------------------

class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, *, retryable: bool = False, details: list | None = None):
        self.status, self.code, self.message, self.retryable, self.details = status, code, message, retryable, details or []


def _error_body(code: str, message: str, retryable: bool = False, details: list | None = None) -> dict[str, Any]:
    return {"error": {"code": code, "message": message, "retryable": retryable,
                      "request_id": str(uuid.uuid4()), "details": details or []}}


def not_found(what: str) -> ApiError:
    return ApiError(404, "not_found", f"{what} не найден")


# --- запросы --------------------------------------------------------------------------------

Unit = Literal["g", "ml", "pcs"]


class Quantity(BaseModel):
    value: float = Field(ge=0, le=1_000_000)
    unit: Unit


class PositiveQuantity(BaseModel):
    value: float = Field(gt=0, le=1_000_000)
    unit: Unit


class PantryAdd(BaseModel):
    ingredient_id: str = Field(min_length=1, max_length=128)
    quantity: PositiveQuantity | None


class PantrySet(BaseModel):
    quantity: Quantity | None


class PurchasedItem(BaseModel):
    ingredient_id: str = Field(min_length=1, max_length=128)
    quantity: PositiveQuantity


class PurchasedBatch(BaseModel):
    items: list[PurchasedItem] = Field(min_length=1, max_length=100)


class Filters(BaseModel):
    q: str = Field(default="", max_length=200)
    mode: Literal["all", "now", "buy_1_3"] = "all"
    max_minutes: int | None = Field(default=None, ge=1)
    max_kcal_per_serving: float | None = Field(default=None, ge=0)
    equipment: list[Literal["stove", "oven", "microwave", "no_cook"]] = ["stove", "oven", "microwave", "no_cook"]
    exclude_allergens: list[str] = []


class RecommendationRequest(BaseModel):
    servings: int = Field(default=2, ge=1, le=12)
    request_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    filters: Filters = Field(default_factory=Filters)
    visibility: Literal["visible", "hidden"] = "visible"
    limit: int = Field(default=20, ge=1, le=100)


class Money(BaseModel):
    minor_units: int = Field(ge=0)
    currency: Literal["RUB"] = "RUB"


class PurchaseRequest(BaseModel):
    servings: int = Field(default=2, ge=1, le=12)
    request_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    filters: Filters = Field(default_factory=Filters)
    budget: Money


class ImportItem(BaseModel):
    line_id: str = Field(min_length=1, max_length=128)
    ingredient_id: str = Field(min_length=1, max_length=128)
    quantity: PositiveQuantity | None


class RecognitionImport(BaseModel):
    recognition_id: str = Field(min_length=1, max_length=128)
    kind: Literal["receipt", "products"]
    items: list[ImportItem] = Field(min_length=1)


# --- приложение -------------------------------------------------------------------------------

def create_app(settings: Settings | None = None, provider_factory: Callable[[], VisionProvider] | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    catalog, catalog_version, catalog_source_name = catalog_source.load(settings)
    index = SearchIndex(catalog)
    state = DemoState.with_demo_pantry(catalog) if settings.demo_pantry else DemoState()
    provider_cache: dict[str, VisionProvider] = {}

    def get_provider() -> VisionProvider:
        if "p" not in provider_cache:
            if provider_factory is not None:
                provider_cache["p"] = provider_factory()
            else:
                from dishgraph.recognition import GigaChatProvider

                try:
                    provider_cache["p"] = GigaChatProvider()
                except RecognitionError as e:
                    raise ApiError(503, "service_unavailable", f"Распознавание не настроено: {e}", retryable=True)
        return provider_cache["p"]

    app = FastAPI(
        title="Почти готово — API",
        version="0.3.0-demo",
        description="Демо-версия сервера по контракту docs/api/openapi.yaml: без авторизации, данные в памяти.",
    )
    app.state.catalog, app.state.state = catalog, state
    api = APIRouter(prefix=API_PREFIX)

    @app.exception_handler(ApiError)
    async def _api_error(_: Request, e: ApiError) -> JSONResponse:
        return JSONResponse(_error_body(e.code, e.message, e.retryable, e.details), status_code=e.status)

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, e: RequestValidationError) -> JSONResponse:
        details = [{"field": ".".join(str(p) for p in err["loc"][1:]) or "body", "code": err["type"], "message": err["msg"]}
                   for err in e.errors()]
        return JSONResponse(_error_body("validation_error", "Ошибка в полях запроса", details=details), status_code=422)

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, e: StarletteHTTPException) -> JSONResponse:
        code = "not_found" if e.status_code == 404 else "http_error"
        return JSONResponse(_error_body(code, str(e.detail)), status_code=e.status_code)

    # --- помощники ---------------------------------------------------------------------------

    def ensure_ingredient(code: str) -> None:
        if code not in catalog.ingredients:
            raise ApiError(422, "validation_error", f"Неизвестный ингредиент {code}",
                           details=[{"field": "ingredient_id", "code": "unknown_id", "message": "Нет в каталоге"}])

    def normalize(code: str, quantity: BaseModel | None) -> dict | None:
        """Quantity из запроса → как хранить в кладовке.

        Граммы и миллилитры взаимозаменяемы (считаем 1:1): «молоко 1000 мл» из чека сохраняется
        как 1000 г, если у продукта в каталоге только граммы. Штуки — только у штучных продуктов.
        """
        if quantity is None:
            return None
        q = quantity.model_dump()
        allowed = contract.allowed_units(catalog, code)
        if q["unit"] in allowed:
            return q
        if q["unit"] in ("g", "ml"):
            return {"value": q["value"], "unit": "ml" if "ml" in allowed and q["unit"] == "g" else "g"}
        raise ApiError(409, "unit_conflict", f"Для «{catalog.name(code)}» единица {q['unit']} не поддерживается")

    def add_quantity(code: str, quantity: dict | None) -> None:
        """Прибавить к кладовке: неизвестное + что угодно = неизвестное; разные единицы — в граммы."""
        if code not in state.pantry:
            state.pantry[code] = quantity
            return
        old = state.pantry[code]
        if old is None or quantity is None:
            state.pantry[code] = None
        elif old["unit"] == quantity["unit"]:
            state.pantry[code] = {"value": old["value"] + quantity["value"], "unit": old["unit"]}
        else:
            a, b = contract.grams(catalog, code, old), contract.grams(catalog, code, quantity)
            state.pantry[code] = None if a is None or b is None else {"value": a + b, "unit": "g"}

    def pantry_response(response: Response | None = None) -> dict[str, Any]:
        if response is not None:
            response.headers["ETag"] = f'"state-{state.state_version}"'
        return {"state_version": state.state_version, "items": contract.pantry_items(catalog, state.pantry)}

    def unknown_codes() -> frozenset[str]:
        return frozenset(code for code, q in state.pantry.items() if q is None)

    def options_for(filters: Filters, servings: int, max_missing: int = 3) -> list:
        opts = reachable_dishes(
            contract.engine_pantry(catalog, state.pantry),
            catalog,
            max_missing=max_missing,
            exclude_allergens=filters.exclude_allergens,
            max_minutes=filters.max_minutes,
            max_kcal=filters.max_kcal_per_serving,
            equipment=set(filters.equipment),
            servings=servings,
        )
        if filters.q.strip():
            q = filters.q.strip().lower()
            opts = [o for o in opts if q in o.recipe.title.lower()]
        return opts

    def page_response(snap: Snapshot, offset: int, limit: int) -> dict[str, Any]:
        items = snap.options[offset : offset + limit]
        more = offset + limit < len(snap.options)
        return {
            "servings": snap.servings,
            "request_id": snap.request_id,
            "snapshot_id": snap.id,
            "expires_at": iso(snap.expires_at),
            "state_version": snap.state_version,
            "catalog_version": catalog_version,
            "visibility": snap.visibility,
            "visible_total": len(snap.options) if snap.visibility == "visible" else 0,
            "hidden_total": 0,
            "unknown_total": 0,
            "items": [contract.recipe_card(catalog, o, snap.unknown_ids, snap.filters["exclude_allergens"]) for o in items],
            "page": {"next_cursor": f"{offset + limit}:{limit}" if more else None, "has_more": more},
        }

    def get_snapshot(snapshot_id: str) -> Snapshot:
        state.cleanup()
        snap = state.snapshots.get(snapshot_id)
        if snap is None:
            raise ApiError(404, "not_found", "Снимок не найден или истёк; создайте подбор заново")
        return snap

    # --- служебное ---------------------------------------------------------------------------

    @api.get("/health", tags=["service"])
    def health() -> dict[str, Any]:
        return {"status": "ok", "api_version": "v1"}

    @api.get("/debug/catalog", tags=["service"], summary="Сводка о загруженном каталоге (не из контракта)")
    def debug_catalog() -> dict[str, Any]:
        return {"source": catalog_source_name, "catalog_version": catalog_version,
                "ingredients": len(catalog.ingredients), "recipes": len(catalog.recipes)}

    @api.get("/me/state", tags=["profile"])
    def me_state() -> dict[str, Any]:
        return {"state_version": state.state_version, "catalog_version": catalog_version, "user_id": DEMO_USER_ID}

    @api.get("/allergens", tags=["dictionaries"])
    def allergens() -> dict[str, Any]:
        used = sorted({a for ing in catalog.ingredients.values() for a in ing.allergens})
        return {"catalog_version": catalog_version,
                "items": [{"id": a, "name": contract.ALLERGEN_NAMES.get(a, a), "support": "supported"} for a in used]}

    # --- ингредиенты и кладовка ------------------------------------------------------------------

    @api.get("/ingredients", tags=["ingredients"])
    def search_ingredients(
        q: str = Query(min_length=1, max_length=200),
        limit: int = Query(20, ge=1, le=100),
        cursor: str | None = None,
    ) -> dict[str, Any]:
        offset = int(cursor) if cursor and cursor.isdigit() else 0
        hits = index.search(q, limit=offset + limit + 1)
        page, more = hits[offset : offset + limit], len(hits) > offset + limit
        return {
            "catalog_version": catalog_version,
            "state_version": state.state_version,
            "items": [contract.ingredient(catalog, h.code) for h in page],
            "page": {"next_cursor": str(offset + limit) if more else None, "has_more": more},
        }

    @api.get("/me/pantry", tags=["pantry"])
    def get_pantry(response: Response) -> dict[str, Any]:
        return pantry_response(response)

    @api.post("/me/pantry/add", tags=["pantry"])
    def pantry_add(body: PantryAdd, response: Response) -> dict[str, Any]:
        ensure_ingredient(body.ingredient_id)
        quantity = normalize(body.ingredient_id, body.quantity)
        with state.lock:
            add_quantity(body.ingredient_id, quantity)
            state.bump()
            return pantry_response(response)

    @api.put("/me/pantry/{ingredient_id}", tags=["pantry"])
    def pantry_set(ingredient_id: str, body: PantrySet, response: Response) -> dict[str, Any]:
        ensure_ingredient(ingredient_id)
        quantity = normalize(ingredient_id, body.quantity)
        with state.lock:
            if quantity is not None and quantity["value"] == 0:
                state.pantry.pop(ingredient_id, None)
            else:
                state.pantry[ingredient_id] = quantity
            state.bump()
            return pantry_response(response)

    @api.delete("/me/pantry/{ingredient_id}", tags=["pantry"])
    def pantry_delete(ingredient_id: str, response: Response) -> dict[str, Any]:
        ensure_ingredient(ingredient_id)
        with state.lock:
            state.pantry.pop(ingredient_id, None)
            state.bump()
            return pantry_response(response)

    @api.post("/me/pantry/purchased", tags=["pantry"])
    def pantry_purchased(body: PurchasedBatch, response: Response) -> dict[str, Any]:
        codes = [i.ingredient_id for i in body.items]
        if len(codes) != len(set(codes)):
            raise ApiError(422, "validation_error", "Ингредиент повторяется в пакете",
                           details=[{"field": "items", "code": "duplicate_ingredient", "message": "Объедините строки"}])
        quantities = []
        for item in body.items:
            ensure_ingredient(item.ingredient_id)
            quantities.append((item.ingredient_id, normalize(item.ingredient_id, item.quantity)))
        with state.lock:
            for code, quantity in quantities:
                add_quantity(code, quantity)
            state.bump()
            return pantry_response(response)

    # --- подбор, граф, покупки ---------------------------------------------------------------

    @api.post("/recommendations", status_code=201, tags=["recommendations"])
    def create_recommendations(body: RecommendationRequest) -> dict[str, Any]:
        options = [] if body.visibility == "hidden" else options_for(body.filters, body.servings)
        if body.filters.mode == "now":
            options = [o for o in options if o.level == 0]
        elif body.filters.mode == "buy_1_3":
            options = [o for o in options if 1 <= o.level <= 3]
        with state.lock:
            state.cleanup()
            snap = Snapshot(
                id=new_id("snap"),
                request_id=body.request_id,
                servings=body.servings,
                filters=body.filters.model_dump(),
                visibility=body.visibility,
                options=options,
                graph=build_graph(options, catalog),  # граф всего снимка, не страницы
                unknown_ids=unknown_codes(),
                state_version=state.state_version,
                expires_at=now() + SNAPSHOT_TTL,
            )
            state.snapshots[snap.id] = snap
        return page_response(snap, 0, body.limit)

    @api.get("/recommendations/{snapshot_id}", tags=["recommendations"])
    def recommendations_page(snapshot_id: str, cursor: str | None = None) -> dict[str, Any]:
        snap = get_snapshot(snapshot_id)
        try:
            offset, limit = (int(x) for x in (cursor or "0:20").split(":"))
        except ValueError:
            raise ApiError(422, "validation_error", "Некорректный cursor")
        return page_response(snap, offset, limit)

    @api.get("/recommendations/{snapshot_id}/graph", tags=["recommendations"])
    def recommendations_graph(snapshot_id: str) -> dict[str, Any]:
        snap = get_snapshot(snapshot_id)
        return {
            "request_id": snap.request_id,
            "snapshot_id": snap.id,
            "expires_at": iso(snap.expires_at),
            "state_version": snap.state_version,
            "catalog_version": catalog_version,
            "servings": snap.servings,
            "filters": snap.filters,
            "visibility": snap.visibility,
            "graph": contract.graph(catalog, snap.graph, snap.options, snap.unknown_ids, snap.filters["exclude_allergens"]),
        }

    @api.get("/recipes/{recipe_id}", tags=["recipes"])
    def recipe_detail(
        recipe_id: str,
        servings: int = Query(2, ge=1, le=12),
        exclude_allergens: list[str] = Query(default=[]),
    ) -> dict[str, Any]:
        try:
            recipe = catalog.recipe(recipe_id)
        except KeyError:
            raise not_found("Рецепт")
        pantry_g = contract.engine_pantry(catalog, state.pantry)
        option = dish_option(recipe, pantry_g, catalog, servings=servings)
        return {
            "state_version": state.state_version,
            "catalog_version": catalog_version,
            "recipe": contract.recipe_card(catalog, option, unknown_codes(), exclude_allergens),
            "ingredients": contract.recipe_items(catalog, option, pantry_g),
            "steps": [{"number": i, "text": t, "minutes": None} for i, t in enumerate(recipe.steps, 1)],
            "shopping_items": contract.missing_shopping_items(catalog, option),
        }

    @api.post("/recommendations/single-purchase", tags=["recommendations"])
    def single_purchase(body: PurchaseRequest) -> dict[str, Any]:
        budget = contract.rub(body.budget.model_dump())
        options = [
            p for p in best_single_purchases(options_for(body.filters, body.servings), catalog) if p.price <= budget + 1e-9
        ]
        return {
            "servings": body.servings,
            "request_id": body.request_id,
            "state_version": state.state_version,
            "catalog_version": catalog_version,
            "options": [
                {"shopping_item": contract.shopping_item(catalog, p.code, p.packs), "unlocked_recipe_ids": list(p.unlocks)}
                for p in options
            ],
            "unpriced_recipe_ids": [],
            "semantics": "alternatives",
            "status": "found" if options else "no_plan",
        }

    @api.post("/recommendations/budget", tags=["recommendations"])
    def budget_plan(body: PurchaseRequest) -> dict[str, Any]:
        plan = best_purchases(options_for(body.filters, body.servings), catalog, contract.rub(body.budget.model_dump()))
        return {
            "servings": body.servings,
            "request_id": body.request_id,
            "state_version": state.state_version,
            "catalog_version": catalog_version,
            "shopping_items": [contract.shopping_item(catalog, c, n) for c, n in sorted(plan.items.items())],
            "unlocked_recipe_ids": list(plan.unlocked),
            "unpriced_recipe_ids": [],
            "semantics": "alternatives",
            "total_cost": contract.money(plan.total_cost) if plan.steps else None,
            "status": "found" if plan.steps else "no_plan",
        }

    # --- распознавание -----------------------------------------------------------------------

    def recognition_response(job: RecognitionJob) -> dict[str, Any]:
        return {
            "id": job.id,
            "kind": job.kind,
            "status": job.status,
            "expires_at": iso(job.expires_at),
            "poll_after_seconds": 1,
            "items": [line.to_dict() for line in job.lines],
            "failure": job.failure,
        }

    @api.post("/recognitions", status_code=202, tags=["recognitions"])
    def create_recognition(
        kind: Literal["receipt", "products"] = Form(...),
        file: UploadFile = File(...),
        provider: VisionProvider = Depends(get_provider),
    ) -> dict[str, Any]:
        image = file.file.read(MAX_IMAGE_BYTES + 1)
        if len(image) > MAX_IMAGE_BYTES:
            raise ApiError(413, "file_too_large", "Изображение больше 10 MiB")
        job = RecognitionJob(id=new_id("rec"), kind=kind, status="succeeded", lines=[], failure=None,
                             expires_at=now() + RECOGNITION_TTL)
        try:
            job.lines = recognize(image, kind, catalog, provider, index)
        except InvalidImage:
            raise ApiError(415, "unsupported_media_type", "Поддерживаются только JPEG и PNG")
        except RecognitionError as e:
            job.status = "failed"
            job.failure = _error_body("service_unavailable", str(e), retryable=True)["error"]
        with state.lock:
            state.cleanup()
            state.recognitions[job.id] = job
        return recognition_response(job)

    @api.get("/recognitions/{recognition_id}", tags=["recognitions"])
    def get_recognition(recognition_id: str) -> dict[str, Any]:
        state.cleanup()
        job = state.recognitions.get(recognition_id)
        if job is None:
            raise ApiError(404, "not_found", "Распознавание не найдено или истекло")
        return recognition_response(job)

    @api.post("/recognition-imports", tags=["recognitions"])
    def import_recognition(body: RecognitionImport) -> dict[str, Any]:
        job = state.recognitions.get(body.recognition_id)
        if job is None:
            raise ApiError(404, "not_found", "Распознавание не найдено или истекло")
        if job.kind != body.kind:
            raise ApiError(409, "context_changed", "kind не совпадает с распознаванием")
        if job.imported:
            raise ApiError(409, "already_imported", "Этот результат уже добавлен в кладовку")
        line_ids = {line.line_id for line in job.lines}
        seen: set[str] = set()
        for item in body.items:
            if item.line_id not in line_ids or item.line_id in seen:
                raise ApiError(422, "validation_error", f"Неизвестная или повторная строка {item.line_id}")
            if body.kind == "receipt" and item.quantity is None:
                raise ApiError(422, "validation_error", "Для чека количество обязательно",
                               details=[{"field": "quantity", "code": "invalid_quantity", "message": "Укажите количество"}])
            seen.add(item.line_id)
            ensure_ingredient(item.ingredient_id)
        quantities = [(i.ingredient_id, normalize(i.ingredient_id, i.quantity)) for i in body.items]
        with state.lock:
            for code, quantity in quantities:
                add_quantity(code, quantity)
            job.imported = True
            state.bump()
            return {
                "operation_id": new_id("op"),
                "recognition_id": job.id,
                "state_version": state.state_version,
                "pantry": contract.pantry_items(catalog, state.pantry),
            }

    app.include_router(api)
    return app
