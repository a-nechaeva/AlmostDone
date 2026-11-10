"""Результат распознавания — в формате контракта API (RecognitionLine, RecognitionCandidate)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal

RecognitionKind = Literal["receipt", "products"]  # фото/скриншот чека или фото продуктов
LineStatus = Literal["matched", "ambiguous", "unmatched"]
UNITS = ("g", "ml", "pcs")

# Лимиты из контракта: JPEG/PNG до 10 MiB
MAX_IMAGE_BYTES = 10 * 1024 * 1024
ALLOWED_MIME = ("image/jpeg", "image/png")


class RecognitionError(Exception):
    """Не удалось распознать: провайдер недоступен или вернул ответ, который нельзя разобрать."""


class InvalidImage(RecognitionError):
    """Файл не подходит: не JPEG/PNG или больше лимита (API: 415 / 413)."""


@dataclass(frozen=True)
class Quantity:
    value: float
    unit: str  # 'g' | 'ml' | 'pcs'

    def to_dict(self) -> dict[str, Any]:
        return {"value": self.value, "unit": self.unit}


@dataclass(frozen=True)
class Candidate:
    code: str  # код ингредиента из каталога
    name: str
    confidence: float  # 0–1

    def to_dict(self) -> dict[str, Any]:
        return {"ingredient_id": self.code, "name": self.name, "confidence": round(self.confidence, 2)}


@dataclass(frozen=True)
class RecognitionLine:
    line_id: str
    raw_name: str  # строка чека или название увиденного продукта
    candidates: tuple[Candidate, ...]  # лучший первым, не больше трёх
    suggested_quantity: Quantity | None  # None, если надёжного основания нет
    status: LineStatus

    @property
    def best(self) -> Candidate | None:
        return self.candidates[0] if self.candidates else None

    def to_dict(self) -> dict[str, Any]:
        return {
            "line_id": self.line_id,
            "raw_name": self.raw_name,
            "candidates": [c.to_dict() for c in self.candidates],
            "suggested_quantity": self.suggested_quantity.to_dict() if self.suggested_quantity else None,
            "status": self.status,
        }
