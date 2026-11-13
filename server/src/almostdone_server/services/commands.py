"""Application commands and results; no transport-specific headers or responses."""
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Command:
    operation: str
    payload: dict = field(default_factory=dict)
    parameters: dict = field(default_factory=dict)
    access_token: str = ""
    expected_version: int | None = None
    idempotency_key: str | None = None


MUTATIONS = frozenset({
    "profile_save", "pantry_add", "pantry_set", "pantry_delete", "pantry_add_purchased",
    "favorites_recipes_put", "favorites_recipes_delete", "favorites_ingredients_put",
    "favorites_ingredients_delete", "recognitions_import",
})
RETRYABLE_COMMANDS = frozenset({
    "pantry_add", "pantry_add_purchased", "recognitions_create", "recognitions_import",
})


@dataclass(frozen=True)
class Result:
    data: dict | bytes | None
    version: int | None = None
