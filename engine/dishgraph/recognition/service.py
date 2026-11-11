"""Распознавание целиком: проверка файла → промпт → провайдер → разбор ответа.

Два запроса: картинка без каталога (строки чека или что видно на фото, с обычными названиями),
затем текст без картинки — сопоставление с коротким списком кандидатов из нашего поиска.
Почему так — см. prompt.py. Провайдер без текстовых запросов: чек — старым способом, одним
запросом со всем каталогом; фото продуктов — только нашим поиском.
"""

from __future__ import annotations

from collections.abc import Callable

from ..models import Catalog
from ..search import SearchIndex
from .models import ALLOWED_MIME, MAX_IMAGE_BYTES, InvalidImage, RecognitionError, RecognitionKind, RecognitionLine
from .parse import (
    SeenProduct,
    build_product_lines,
    parse_mapping,
    parse_products,
    parse_receipt_lines,
    parse_response,
    shortlist,
)
from .prompt import build_mapping_prompt, build_products_prompt, build_receipt_prompt, build_receipt_read_prompt
from .providers import VisionProvider


def detect_mime(image: bytes) -> str | None:
    """Тип по первым байтам файла — не доверяем имени и заголовку Content-Type."""
    if image.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if image.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    return None


def _call(fn: Callable[[], str]) -> str:
    try:
        return fn()
    except RecognitionError:
        raise
    except Exception as e:  # сеть, авторизация, лимиты провайдера
        raise RecognitionError(f"Провайдер распознавания недоступен: {e}") from e


def recognize(
    image: bytes,
    kind: RecognitionKind,
    catalog: Catalog,
    provider: VisionProvider,
    index: SearchIndex | None = None,
) -> list[RecognitionLine]:
    """Распознать продукты на фото чека (kind="receipt") или фото продуктов (kind="products").

    InvalidImage — файл не JPEG/PNG или больше 10 MiB (API: 415 / 413).
    RecognitionError — провайдер недоступен или ответ нельзя разобрать (API: status failed / 503).
    Результат всегда требует подтверждения пользователем.
    """
    if kind not in ("receipt", "products"):
        raise ValueError(f"Неизвестный вид распознавания: {kind!r}")
    if len(image) > MAX_IMAGE_BYTES:
        raise InvalidImage(f"Изображение больше {MAX_IMAGE_BYTES // (1024 * 1024)} MiB")
    mime = detect_mime(image)
    if mime not in ALLOWED_MIME:
        raise InvalidImage("Поддерживаются только JPEG и PNG")
    index = index or SearchIndex(catalog)
    complete_text = getattr(provider, "complete_text", None)

    if kind == "receipt":
        if complete_text is None:
            text = _call(lambda: provider.complete(image, mime, build_receipt_prompt(catalog)))
            return parse_response(text, catalog, index)
        text = _call(lambda: provider.complete(image, mime, build_receipt_read_prompt()))
        lines = parse_receipt_lines(text)
        if lines is None:  # модель сразу дала коды каталога — второй запрос не нужен
            return parse_response(text, catalog, index)
        seen = lines
    else:
        seen = parse_products(_call(lambda: provider.complete(image, mime, build_products_prompt())))
    if not seen:
        return []
    return build_product_lines(seen, _map(seen, catalog, index, complete_text), catalog, index)


def _map(
    seen: list[SeenProduct],
    catalog: Catalog,
    index: SearchIndex,
    complete_text: Callable[[str], str] | None,
) -> dict[int, dict[str, float]]:
    """Шаг 2: сопоставление с коротким списком. Не удалось — строки соберёт наш поиск."""
    codes = shortlist(seen, index)
    if complete_text is None or not codes:
        return {}
    try:
        answer = _call(lambda: complete_text(build_mapping_prompt([s.label for s in seen], catalog, codes)))
        return parse_mapping(answer, len(seen), catalog)
    except RecognitionError:
        return {}
