"""Разбор и проверка ответа LLM.

LLM может вернуть JSON в markdown-блоке, выдуманные коды, уверенность вне 0–1, килограммы вместо
граммов. Здесь всё это нормализуется; в результат попадают только ингредиенты из каталога.
"""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from typing import Any

from ..models import Catalog
from ..search import SearchIndex
from .models import Candidate, Quantity, RecognitionError, RecognitionLine

MAX_ITEMS = 100
MAX_CANDIDATES = 3
MAX_RAW_NAME = 200
MAX_QUANTITY = 1_000_000

MATCHED_MIN = 0.8  # лучший кандидат не ниже...
MATCHED_GAP = 0.2  # ...и отрыв от второго не меньше
FALLBACK_WEIGHT = 0.6  # кандидаты из нашего поиска: уверенность = score × 0.6, «matched» не бывает
FALLBACK_MIN_SCORE = 0.9  # наш поиск берём, только если строка или её первое слово — начало названия
SUPPORT_MIN = 0.5  # если выбор модели слабо похож на строку...
UNSUPPORTED_CAP = 0.7  # ...её уверенность не выше 0.7: строка уходит на подтверждение
DROP_BELOW = 0.3  # совсем не похож («перец болгарский» → помидоры, «колбаса» → сосиски) — убираем

# единица -> (наша единица, множитель)
_UNITS = {
    "g": ("g", 1), "г": ("g", 1), "гр": ("g", 1), "kg": ("g", 1000), "кг": ("g", 1000),
    "ml": ("ml", 1), "мл": ("ml", 1), "l": ("ml", 1000), "л": ("ml", 1000),
    "pcs": ("pcs", 1), "шт": ("pcs", 1),
}

_FENCE_RE = re.compile(r"^```[a-zA-Z]*\s*|\s*```$")


def extract_json(text: str) -> Any:
    """JSON из ответа модели: снимает ```json ... ``` и лишний текст вокруг объекта."""
    s = _FENCE_RE.sub("", text.strip())
    start, end = s.find("{"), s.rfind("}")
    if start == -1 or end < start:
        raise RecognitionError("В ответе модели нет JSON-объекта")
    try:
        return json.loads(s[start : end + 1])
    except json.JSONDecodeError as e:
        raise RecognitionError(f"Модель вернула некорректный JSON: {e}") from e


def _confidence(value: Any) -> float | None:
    try:
        c = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(c):
        return None
    return min(max(c, 0.0), 1.0)


def _quantity(raw: Any) -> Quantity | None:
    if not isinstance(raw, dict):
        return None
    unit = str(raw.get("unit", "")).strip().lower().rstrip(".")
    if unit not in _UNITS:
        return None
    try:
        value = float(str(raw.get("value")).replace(",", "."))
    except (TypeError, ValueError):
        return None
    our_unit, factor = _UNITS[unit]
    value *= factor
    if not math.isfinite(value) or value <= 0 or value > MAX_QUANTITY:
        return None
    if our_unit == "pcs":
        if abs(value - round(value)) > 1e-6:
            return None  # «1,5 штуки» — не доверяем
        value = float(round(value))
    return Quantity(value=round(value, 2), unit=our_unit)


def _status(candidates: list[Candidate]) -> str:
    if not candidates:
        return "unmatched"
    top = candidates[0].confidence
    second = candidates[1].confidence if len(candidates) > 1 else 0.0
    return "matched" if top >= MATCHED_MIN and top - second >= MATCHED_GAP else "ambiguous"


_WORD_RE = re.compile(r"[а-яёa-z]{3,}", re.IGNORECASE)


def _fallback_candidates(raw_name: str, index: SearchIndex, catalog: Catalog) -> dict[str, float]:
    """Кандидаты из нашего поиска, если модель не дала подходящий код.

    Ищем всю строку и её первое слово: на чеке сначала идёт сам продукт, потом уточнения
    («КАРТОФЕЛЬ ВЕС», «МОЛОКО ПАСТ.»). Берём только надёжные совпадения — начало названия
    или синонима. Опечатки и остальные слова не ищем: иначе «Сельдь филе» находилась как
    куриное филе, «Сельдь под шубой» — как масло подсолнечное, «салат» — как сахар.
    Базовые продукты (соль, перец, масло, вода) не предлагаем: «болгарский перец» — не чёрный
    молотый, «оливковое масло» — не подсолнечное, а дома они «есть всегда».
    Уверенность не выше FALLBACK_WEIGHT, такая строка всегда требует подтверждения.
    """
    words = _WORD_RE.findall(raw_name)
    queries = [raw_name, *words[:1]]
    best: dict[str, float] = {}
    for query in queries:
        for hit in index.search(query, limit=MAX_CANDIDATES):
            if hit.score >= FALLBACK_MIN_SCORE and not catalog.ingredients[hit.code].is_staple:
                best[hit.code] = max(best.get(hit.code, 0.0), round(hit.score * FALLBACK_WEIGHT, 2))
    return best


def _merge_duplicates(lines: list[RecognitionLine]) -> list[RecognitionLine]:
    """Одинаковые строки (то же название и тот же продукт) — в одну, количество складываем.

    На чеке товар часто пробит несколько раз, на фото — несколько одинаковых упаковок.
    Если у какой-то из строк количество неизвестно или единицы разные — итог неизвестен (None).
    """
    groups: dict[tuple[str, str | None], list[RecognitionLine]] = {}
    for line in lines:
        key = (line.raw_name.lower(), line.best.code if line.best else None)
        groups.setdefault(key, []).append(line)

    merged: list[RecognitionLine] = []
    for group in groups.values():
        first = group[0]
        quantity = first.suggested_quantity
        if len(group) > 1:
            qs = [l.suggested_quantity for l in group]
            if all(q is not None for q in qs) and len({q.unit for q in qs}) == 1:  # type: ignore[union-attr]
                total = sum(q.value for q in qs)  # type: ignore[union-attr]
                quantity = Quantity(value=round(total, 2), unit=qs[0].unit) if total <= MAX_QUANTITY else None  # type: ignore[union-attr]
            else:
                quantity = None
        merged.append(
            RecognitionLine(
                line_id=f"line-{len(merged) + 1}",
                raw_name=first.raw_name,
                candidates=first.candidates,
                suggested_quantity=quantity,
                status=first.status,
            )
        )
    return merged


def _clean_name(value: Any) -> str:
    return " ".join(str(value or "").split())[:MAX_RAW_NAME]


def _candidate_scores(raw: Any, catalog: Catalog) -> dict[str, float]:
    """[{"code", "confidence"}, ...] → {код: уверенность}: только коды из каталога, дубли — по максимуму."""
    best: dict[str, float] = {}
    for cand in raw if isinstance(raw, list) else []:
        if not isinstance(cand, dict):
            continue
        code = str(cand.get("code") or "").strip()
        conf = _confidence(cand.get("confidence"))
        if code in catalog.ingredients and conf is not None:
            best[code] = max(conf, best.get(code, 0.0))
    return best


def _build_line(
    raw_name: str,
    scores: dict[str, float],
    quantity: Quantity | None,
    catalog: Catalog,
    index: SearchIndex | None,
    visual_confidence: float | None = None,
) -> RecognitionLine | None:
    best = dict(scores)
    # Модель бывает уверена там, где не должна («колбаса» → сосиски на 1.00, болгарский перец →
    # помидоры). Сверяем её выбор с названием: совсем не похоже — убираем, слабо похоже —
    # уверенность не выше 0.7, строка уходит на подтверждение.
    if raw_name and index is not None:
        for code in list(best):
            support = index.similarity(raw_name, code)
            if support < DROP_BELOW:
                del best[code]
            elif support < SUPPORT_MIN:
                best[code] = min(best[code], UNSUPPORTED_CAP)
    if not best and raw_name and index is not None:
        best = _fallback_candidates(raw_name, index, catalog)
    # фото продуктов: если модель не уверена, что видит именно этот продукт, сопоставление не надёжнее
    if visual_confidence is not None:
        best = {c: min(v, visual_confidence) for c, v in best.items()}

    if not raw_name and not best:
        return None
    candidates = sorted(
        (Candidate(code=c, name=catalog.name(c), confidence=v) for c, v in best.items()),
        key=lambda c: (-c.confidence, c.name),
    )[:MAX_CANDIDATES]
    return RecognitionLine(
        line_id="",  # номера проставляет _merge_duplicates
        raw_name=raw_name or candidates[0].name,
        candidates=tuple(candidates),
        suggested_quantity=quantity,
        status=_status(candidates),  # type: ignore[arg-type]
    )


def _items(data: Any, key: str) -> list[Any]:
    items = data.get(key) if isinstance(data, dict) else None
    if not isinstance(items, list):
        raise RecognitionError(f"В ответе модели нет списка {key}")
    return items[:MAX_ITEMS]


# --- чек: один запрос -----------------------------------------------------------------

def parse_response(text: str, catalog: Catalog, index: SearchIndex | None = None) -> list[RecognitionLine]:
    """Ответ модели на чек (строки + кандидаты из каталога) → строки распознавания."""
    lines = []
    for item in _items(extract_json(text), "items"):
        if not isinstance(item, dict):
            continue
        line = _build_line(
            _clean_name(item.get("raw_name")),
            _candidate_scores(item.get("candidates"), catalog),
            _quantity(item.get("quantity")),
            catalog,
            index,
        )
        if line is not None:
            lines.append(line)
    return _merge_duplicates(lines)


# --- фото продуктов: картинка → список, текст → сопоставление ----------------------------

@dataclass(frozen=True)
class SeenProduct:
    """Продукт, который модель увидела на фото (до сопоставления с каталогом)."""

    name: str
    confidence: float
    quantity: Quantity | None


def _count(value: Any) -> int | None:
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(n) or n < 1 or n > 1000 or abs(n - round(n)) > 1e-6:
        return None
    return int(round(n))


def parse_products(text: str) -> list[SeenProduct]:
    """Ответ модели на фото продуктов → что увидено, с количеством.

    quantity — вес/объём одной упаковки, count — сколько упаковок: итог = quantity × count.
    Если видно только число штук — count штук.
    """
    seen = []
    for item in _items(extract_json(text), "items"):
        if not isinstance(item, dict):
            continue
        name = _clean_name(item.get("name") or item.get("raw_name"))
        if not name:
            continue
        confidence = _confidence(item.get("confidence"))
        per_pack = _quantity(item.get("quantity"))
        count = _count(item.get("count"))
        if per_pack is not None and count is not None:
            total = per_pack.value * count
            quantity = Quantity(value=round(total, 2), unit=per_pack.unit) if total <= MAX_QUANTITY else None
        elif per_pack is not None:
            quantity = per_pack
        elif count is not None and count > 1:
            # «1 штука» без веса ничего не говорит (одна пачка майонеза) — оставляем неизвестным
            quantity = Quantity(value=float(count), unit="pcs")
        else:
            quantity = None
        seen.append(SeenProduct(name=name, confidence=0.5 if confidence is None else confidence, quantity=quantity))
    return seen


def parse_mapping(text: str, count: int, catalog: Catalog) -> dict[int, dict[str, float]]:
    """Ответ на сопоставление → {номер найденного продукта (с 1): {код: уверенность}}."""
    mapping: dict[int, dict[str, float]] = {}
    for match in _items(extract_json(text), "matches"):
        if not isinstance(match, dict):
            continue
        number = _count(match.get("index"))
        if number is None or number > count:
            continue
        scores = _candidate_scores(match.get("candidates"), catalog)
        for code, conf in scores.items():
            mapping.setdefault(number, {})[code] = max(conf, mapping.get(number, {}).get(code, 0.0))
    return mapping


def build_product_lines(
    seen: list[SeenProduct],
    mapping: dict[int, dict[str, float]],
    catalog: Catalog,
    index: SearchIndex | None = None,
) -> list[RecognitionLine]:
    """Увиденные продукты + сопоставление с каталогом → строки распознавания."""
    lines = []
    for number, product in enumerate(seen, 1):
        line = _build_line(product.name, mapping.get(number, {}), product.quantity, catalog, index, product.confidence)
        if line is not None:
            lines.append(line)
    return _merge_duplicates(lines)
