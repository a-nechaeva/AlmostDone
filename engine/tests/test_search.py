import pytest

from dishgraph import SearchIndex, load_catalog, search_ingredients
from dishgraph.search import levenshtein, normalize, trigram_similarity


@pytest.fixture(scope="module")
def index():
    return SearchIndex(load_catalog())


def codes(hits):
    return [h.code for h in hits]


# Те же случаи, что проверялись на SQL-функции search_ingredients в БД
@pytest.mark.parametrize(
    "query, expected",
    [
        ("яйц", "egg"),            # начало названия
        ("яйца", "egg"),           # синоним
        ("картошк", "potato"),     # начало синонима «картошка»
        ("сыр", "cheese"),         # начало «Сыр твёрдый»
        ("твёрд", "cheese"),       # начало второго слова
        ("малако", "milk"),        # 2 опечатки
        ("кортофель", "potato"),   # опечатка в длинном слове
        ("маслo", "butter"),       # латинская «o» вместо русской
        ("мед", "honey"),          # «е» вместо «ё»
        ("  ЯЙЦ  ", "egg"),        # регистр и пробелы
        ("помид", "tomato"),
    ],
)
def test_finds(index, query, expected):
    assert expected in codes(index.search(query))


def test_typo_prefers_closer_word(index):
    # и «молоко», и «макароны» начинаются с 2 отличий от «малако», но молоко ближе целиком
    assert codes(index.search("малако"))[0] == "milk"


def test_prefix_ranks_first(index):
    hits = index.search("мол")
    assert hits[0].code == "milk"
    assert hits[0].score == 1.0


def test_one_hit_per_ingredient(index):
    hits = index.search("яйц")  # совпадает и с названием, и с синонимами
    assert codes(hits).count("egg") == 1


def test_matched_shows_alias(index):
    hit = next(h for h in index.search("картошк") if h.code == "potato")
    assert hit.matched == "картошка"
    assert hit.name == "Картофель"


@pytest.mark.parametrize("query", ["", "   ", "%", "_", "ъъъъъъ", "а" * 300])
def test_nothing_for_garbage(index, query):
    assert index.search(query) == []


def test_limit(index):
    assert len(index.search("м", limit=3)) == 3
    assert index.search("м", limit=0) == []


def test_sorted_by_score(index):
    scores = [h.score for h in index.search("масло")]
    assert scores == sorted(scores, reverse=True)


def test_to_dict(index):
    assert index.search("малако")[0].to_dict() == {
        "code": "milk", "name": "Молоко 2,5%", "matched": "Молоко 2,5%", "score": 0.6,
    }


def test_one_shot_helper():
    assert codes(search_ingredients(load_catalog(), "яйц")) == ["egg"]


def test_helpers():
    assert normalize("  Мёд ") == "мед"
    assert levenshtein("малако", "молоко") == 2
    assert levenshtein("", "abc") == 3
    assert trigram_similarity("молоко", "молоко") == 1.0
    assert trigram_similarity("молоко", "гречка") == 0.0
