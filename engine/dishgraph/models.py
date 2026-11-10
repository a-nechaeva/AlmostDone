"""Модели данных движка. Поля и названия совпадают со схемой БД (db/schema.sql)"""

from __future__ import annotations

from dataclasses import dataclass

EQUIPMENT = ("microwave", "stove", "oven")


@dataclass(frozen=True)
class Ingredient:
    code: str  # "egg" — ingredients.code
    name: str  # "Яйцо куриное"
    package_g: float  # вес одной упаковки, г
    package_price: float  # средняя цена упаковки, ₽
    kcal: float  # на 100 г
    protein: float  # на 100 г
    fat: float  # на 100 г
    carbs: float  # на 100 г
    is_staple: bool = False  # соль, вода, масло: «есть всегда», не докупаем
    allergens: frozenset[str] = frozenset()  # коды: {"eggs", "milk"}
    aliases: tuple[str, ...] = ()  # синонимы для поиска и распознавания чеков
    display_unit: str = "g"  # 'g' | 'ml' | 'pcs'
    grams_per_piece: float | None = None  # для штучных: яйцо = 55 г


@dataclass(frozen=True)
class RecipeItem:
    code: str  # код ингредиента
    qty_g: float  # граммы на весь рецепт (на все порции)
    is_optional: bool = False  # «по вкусу»: не докупаем, не считаем в КБЖУ


@dataclass(frozen=True)
class Recipe:
    id: str  # recipes.id (строкой)
    title: str
    cook_time_min: int
    servings: int
    items: tuple[RecipeItem, ...]
    needs_microwave: bool = False
    needs_stove: bool = False
    needs_oven: bool = False
    steps: tuple[str, ...] = ()
    description: str | None = None

    @property
    def required_items(self) -> tuple[RecipeItem, ...]:
        return tuple(i for i in self.items if not i.is_optional)

    @property
    def equipment(self) -> frozenset[str]:
        """Какая техника нужна: подмножество {"microwave", "stove", "oven"}."""
        flags = {"microwave": self.needs_microwave, "stove": self.needs_stove, "oven": self.needs_oven}
        return frozenset(k for k, v in flags.items() if v)


@dataclass(frozen=True)
class Catalog:
    """Все данные, с которыми работает движок."""

    ingredients: dict[str, Ingredient]  # код -> ингредиент
    recipes: tuple[Recipe, ...]

    @property
    def staples(self) -> frozenset[str]: # коды базовых продуктов
        return frozenset(c for c, i in self.ingredients.items() if i.is_staple)

    def name(self, code: str) -> str:
        return self.ingredients[code].name

    def recipe(self, recipe_id: str) -> Recipe:
        for r in self.recipes:
            if r.id == recipe_id:
                return r
        raise KeyError(recipe_id)

    def packs_needed(self, code: str, grams: float) -> int:
        """Сколько целых упаковок нужно, чтобы докупить grams"""
        if grams <= 0:
            return 0
        return _ceil_div(grams, self.ingredients[code].package_g)

    def pack_cost(self, code: str, grams: float) -> float:
        """Стоимость покупки grams целыми упаковками."""
        return self.packs_needed(code, grams) * self.ingredients[code].package_price


def _ceil_div(a: float, b: float) -> int: # деление с округлением вверх с маленьким допуском
    q = int(a // b)
    return q if q * b >= a - 1e-9 else q + 1
