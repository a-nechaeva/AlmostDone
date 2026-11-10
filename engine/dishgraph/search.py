"""Автодополнение ингредиентов: по названию и синонимам, с опечатками.

Перенесено из бывшей SQL-функции search_ingredients. Оценка совпадения (0–1):
  1.0 — запрос — начало названия или синонима («яйц» → яйцо, «картошк» → картофель);
  0.9 — запрос — начало другого слова в названии («твёрд» → сыр твёрдый);
  0.5–0.7 — до 2 опечаток в начале названия, для запросов от 4 букв («малако» → молоко);
            чем меньше правок до всего слова, тем выше;
  иначе — триграммное сходство с одним из слов (как pg_trgm), если оно не ниже 0.5.
Регистр, пробелы по краям и «ё»/«е» не важны.

Индекс строится один раз при старте сервера: SearchIndex(catalog).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from .models import Catalog

MAX_QUERY_LEN = 64
MIN_SCORE = 0.5
TYPO_MIN_LEN = 4
TYPO_MAX_EDITS = 2

_WORD_RE = re.compile(r"[0-9a-zа-я]+")


def normalize(text: str) -> str:
    """Нижний регистр, без пробелов по краям, ё = е."""
    return text.strip().lower().replace("ё", "е")


def trigrams(word: str) -> frozenset[str]:
    """Триграммы слова, как в pg_trgm: слово дополняется двумя пробелами слева и одним справа."""
    padded = f"  {word} "
    return frozenset(padded[i : i + 3] for i in range(len(padded) - 2))


def trigram_similarity(a: str, b: str) -> float:
    ta, tb = trigrams(a), trigrams(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def levenshtein(a: str, b: str) -> int:
    """Число вставок, удалений и замен, чтобы из a получить b."""
    if len(a) < len(b):
        a, b = b, a
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def score(query: str, term: str) -> float:
    """Насколько нормализованный term подходит под нормализованный query (0–1)."""
    if term.startswith(query):
        return 1.0
    words = _WORD_RE.findall(term)
    if any(w.startswith(query) for w in words):
        return 0.9
    best = 0.0
    if len(query) >= TYPO_MIN_LEN and levenshtein(query, term[: len(query)]) <= TYPO_MAX_EDITS:
        # чем ближе запрос ко всему первому слову, тем выше: «малако» ближе к «молоко» (2 правки),
        # чем к «макароны» (4), хотя начало обоих слов отличается от запроса на 2 буквы
        first_word = words[0] if words else term
        best = max(MIN_SCORE, 0.7 - 0.05 * levenshtein(query, first_word))
    q_words = _WORD_RE.findall(query)
    if len(q_words) == 1:
        best = max([best, *(trigram_similarity(q_words[0], w) for w in words)])
    return best


@dataclass(frozen=True)
class SearchHit:
    code: str
    name: str
    matched: str  # по какому названию или синониму нашлось
    score: float

    def to_dict(self) -> dict[str, Any]:
        return {"code": self.code, "name": self.name, "matched": self.matched, "score": round(self.score, 2)}


class SearchIndex:
    """Нормализованные названия и синонимы всех ингредиентов каталога."""

    def __init__(self, catalog: Catalog) -> None:
        self._terms: list[tuple[str, str, str]] = []  # (код, исходный текст, нормализованный)
        self._names: dict[str, str] = {}
        for code, ing in catalog.ingredients.items():
            self._names[code] = ing.name
            for term in (ing.name, *ing.aliases):
                self._terms.append((code, term, normalize(term)))

    def search(self, query: str, limit: int = 10) -> list[SearchHit]:
        q = normalize(query)[:MAX_QUERY_LEN]
        if not q or limit <= 0:
            return []
        best: dict[str, SearchHit] = {}
        for code, term, norm in self._terms:
            s = score(q, norm)
            if s >= MIN_SCORE and (code not in best or s > best[code].score):
                best[code] = SearchHit(code=code, name=self._names[code], matched=term, score=s)
        hits = sorted(best.values(), key=lambda h: (-h.score, len(h.name), h.name))
        return hits[:limit]

    def similarity(self, text: str, code: str) -> float:
        """Насколько текст похож на конкретный продукт (0–1): лучшая оценка по всей строке
        и по каждому её слову от 3 букв, по названию и синонимам продукта.

        Нужна распознаванию: проверить, что выбранный моделью продукт хоть как-то похож
        на строку чека («колбаса» на «Сосиски» не похожа, «Хлеб ржаной» на «Хлеб» — похож).
        """
        q = normalize(text)[:MAX_QUERY_LEN]
        if not q:
            return 0.0
        queries = [q, *(w for w in _WORD_RE.findall(q) if len(w) >= 3)]
        return max(
            (score(query, norm) for c, _, norm in self._terms if c == code for query in queries),
            default=0.0,
        )


def search_ingredients(catalog: Catalog, query: str, limit: int = 10) -> list[SearchHit]:
    """Разовый поиск без заранее построенного индекса (для тестов и демо)."""
    return SearchIndex(catalog).search(query, limit)
