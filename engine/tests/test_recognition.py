import json
from types import SimpleNamespace

import pytest

from dishgraph import SearchIndex, load_catalog
from dishgraph.recognition import (
    MAX_IMAGE_BYTES,
    FakeProvider,
    GigaChatProvider,
    InvalidImage,
    RecognitionError,
    build_prompt,
    detect_mime,
    extract_json,
    parse_mapping,
    parse_products,
    parse_response,
    recognize,
)
from dishgraph.recognition.cli import main as cli_main
from dishgraph.recognition.providers import _response_text

JPEG = b"\xff\xd8\xff\xe0" + b"\0" * 100
PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 100


@pytest.fixture(scope="module")
def catalog():
    return load_catalog()


@pytest.fixture(scope="module")
def index(catalog):
    return SearchIndex(catalog)


def answer(*items):
    return json.dumps({"items": list(items)}, ensure_ascii=False)


def item(raw, *cands, quantity=None):
    return {"raw_name": raw, "candidates": [{"code": c, "confidence": v} for c, v in cands], "quantity": quantity}


# --- промпт ----------------------------------------------------------------------------

def test_prompt_lists_catalog(catalog):
    prompt = build_prompt("receipt", catalog)
    assert "Яйцо куриное (яйца, яйцо с1, яйцо с0) → egg" in prompt
    assert "Сметана 15% (сметана) → sour_cream" in prompt
    assert '{"items": [' in prompt
    assert "по-русски" in prompt and "колбаса — не сосиски" in prompt


def test_prompt_depends_on_kind(catalog):
    assert "кассового чека" in build_prompt("receipt", catalog)
    assert "холодильник" in build_prompt("products", catalog)
    assert "кассового чека" not in build_prompt("products", catalog)


# --- извлечение JSON -------------------------------------------------------------------

def test_extract_json_from_markdown_fence():
    assert extract_json('```json\n{"items": []}\n```') == {"items": []}


def test_extract_json_with_text_around():
    assert extract_json('Вот результат: {"items": []} Надеюсь, помог!') == {"items": []}


@pytest.mark.parametrize("text", ["", "не знаю", "{items: [}"])
def test_extract_json_garbage(text):
    with pytest.raises(RecognitionError):
        extract_json(text)


# --- разбор ответа ---------------------------------------------------------------------

def test_parse_valid_answer(catalog, index):
    lines = parse_response(
        answer(item("ЯЙЦО С1 10ШТ", ("egg", 0.95), quantity={"value": 10, "unit": "pcs"}),
               item("МОЛОКО ПАСТ.2,5% 1Л", ("milk", 0.9), quantity={"value": 1, "unit": "l"})),
        catalog, index,
    )
    assert [l.line_id for l in lines] == ["line-1", "line-2"]
    assert lines[0].best.code == "egg" and lines[0].best.name == "Яйцо куриное"
    assert lines[0].status == "matched"
    assert lines[0].suggested_quantity.to_dict() == {"value": 10.0, "unit": "pcs"}
    assert lines[1].suggested_quantity.to_dict() == {"value": 1000.0, "unit": "ml"}


def test_unknown_code_falls_back_to_search(catalog, index):
    (line,) = parse_response(answer(item("молоко", ("unicorn", 0.99))), catalog, index)
    assert line.best.code == "milk"
    assert line.best.confidence <= 0.6  # из нашего поиска — только с подтверждением
    assert line.status == "ambiguous"


def test_fallback_by_words_of_receipt_line(catalog, index):
    (line,) = parse_response(answer(item("КАРТОФЕЛЬ ВЕС")), catalog, index)
    assert line.best.code == "potato"
    assert line.status == "ambiguous"


def test_fallback_prefers_first_word(catalog, index):
    # «паст» — начало синонима «паста» у макарон, но продукт здесь — молоко
    (line,) = parse_response(answer(item("МОЛОКО ПАСТ.2,5%")), catalog, index)
    assert line.best.code == "milk"


# Случаи из прогона на реальных фото
@pytest.mark.parametrize("raw", ["Сельдь филе", 'Сельдь "Под шубой"', "салат", "Свинина охл. шейка"])
def test_fallback_does_not_guess(catalog, index, raw):
    (line,) = parse_response(answer(item(raw)), catalog, index)
    assert line.status == "unmatched", line.candidates


@pytest.mark.parametrize("raw, code", [("колбаса", "sausage"), ("перец болгарский желтый", "tomato"), ("мясо", "minced_meat")])
def test_unrelated_model_choice_dropped(catalog, index, raw, code):
    # модель уверенно выбрала продукт, который совсем не похож на название, — подсказку убираем
    (line,) = parse_response(answer(item(raw, (code, 1.0))), catalog, index)
    assert line.status == "unmatched"


def test_weakly_related_model_choice_capped(catalog, index):
    # «макарошки» похожи на «макароны» лишь отчасти — оставляем, но на подтверждение
    (line,) = parse_response(answer(item("макарошки", ("pasta", 1.0))), catalog, index)
    assert line.best.code == "pasta" and line.best.confidence == 0.7
    assert line.status == "ambiguous"


@pytest.mark.parametrize(
    "raw, code",
    [("Хлеб ржаной", "bread"), ("Томаты тепличные", "tomato"), ("курица", "chicken_breast"),
     ("Лук репка", "onion"), ("БАТОН НАР", "bread"), ("сыр твердый", "cheese")],
)
def test_supported_model_choice_kept(catalog, index, raw, code):
    (line,) = parse_response(answer(item(raw, (code, 1.0))), catalog, index)
    assert line.best.confidence == 1.0 and line.status == "matched"


def test_duplicates_merged_with_quantities(catalog, index):
    q = {"value": 200, "unit": "g"}
    lines = parse_response(
        answer(item("Творог", ("cottage_cheese", 1.0), quantity=q), item("Творог", ("cottage_cheese", 1.0), quantity=q),
               item("Творог", ("cottage_cheese", 1.0), quantity=q), item("Напиток кисломолочный"),
               item("Напиток кисломолочный")),
        catalog, index,
    )
    assert [(l.line_id, l.raw_name) for l in lines] == [("line-1", "Творог"), ("line-2", "Напиток кисломолочный")]
    assert lines[0].suggested_quantity.to_dict() == {"value": 600.0, "unit": "g"}


def test_duplicates_with_unknown_quantity(catalog, index):
    lines = parse_response(
        answer(item("Молоко", ("milk", 1.0), quantity={"value": 1, "unit": "l"}), item("Молоко", ("milk", 1.0))),
        catalog, index,
    )
    assert len(lines) == 1 and lines[0].suggested_quantity is None


# --- фото продуктов: два шага --------------------------------------------------------------

def seen(*items):
    return json.dumps({"items": [dict(name=n, **kw) for n, kw in items]}, ensure_ascii=False)


def matches(*items):
    return json.dumps({"matches": [{"index": i, "candidates": [{"code": c, "confidence": v} for c, v in cands]}
                                   for i, cands in items]})


def test_products_two_steps(catalog, index):
    provider = FakeProvider([
        seen(("творог", {"confidence": 0.95, "count": 5, "quantity": {"value": 200, "unit": "g"}}),
             ("куриные яйца", {"confidence": 0.9, "count": 10}),
             ("шампиньоны", {"confidence": 0.9})),
        matches((1, [("cottage_cheese", 0.95)]), (2, [("egg", 0.95)]), (3, [])),
    ])
    lines = recognize(JPEG, "products", catalog, provider, index)
    vision_prompt, mapping_prompt = provider.calls[0][2], provider.calls[1][2]
    assert "→ egg" not in vision_prompt          # на шаге с картинкой каталога нет
    assert provider.calls[1][0] == 0             # сопоставление — без картинки
    assert "1. творог" in mapping_prompt and "→ cottage_cheese" in mapping_prompt
    assert [(l.raw_name, l.best.code if l.best else None, l.status) for l in lines] == [
        ("творог", "cottage_cheese", "matched"),
        ("куриные яйца", "egg", "matched"),
        ("шампиньоны", None, "unmatched"),
    ]
    assert lines[0].suggested_quantity.to_dict() == {"value": 1000.0, "unit": "g"}  # 5 × 200 г
    assert lines[1].suggested_quantity.to_dict() == {"value": 10.0, "unit": "pcs"}


def test_products_unsure_vision_caps_confidence(catalog, index):
    provider = FakeProvider([seen(("сыр", {"confidence": 0.4})), matches((1, [("cheese", 1.0)]))])
    (line,) = recognize(JPEG, "products", catalog, provider, index)
    assert line.best.confidence == 0.4 and line.status == "ambiguous"


def test_products_mapping_failure_falls_back_to_search(catalog, index):
    provider = FakeProvider([seen(("молоко", {"confidence": 0.9})), "не JSON"])
    (line,) = recognize(JPEG, "products", catalog, provider, index)
    assert line.best.code == "milk" and line.status == "ambiguous"


def test_products_provider_without_text_requests(catalog, index):
    class VisionOnly:
        def complete(self, image, mime, prompt):
            return seen(("картофель", {"confidence": 0.9}))

    (line,) = recognize(JPEG, "products", catalog, VisionOnly(), index)
    assert line.best.code == "potato"


def test_products_nothing_seen_skips_mapping(catalog, index):
    provider = FakeProvider(['{"items": []}'])
    assert recognize(JPEG, "products", catalog, provider, index) == []
    assert len(provider.calls) == 1


def test_mapping_ignores_bad_indexes(catalog):
    text = matches((0, [("milk", 1.0)]), (5, [("egg", 1.0)]), (2, [("cheese", 0.9), ("unicorn", 1.0)]))
    assert parse_mapping(text, 2, catalog) == {2: {"cheese": 0.9}}


@pytest.mark.parametrize(
    "item, expected",
    [
        ({"count": 3, "quantity": {"value": 0.2, "unit": "кг"}}, {"value": 600.0, "unit": "g"}),
        ({"count": 6}, {"value": 6.0, "unit": "pcs"}),
        ({"quantity": {"value": 1, "unit": "л"}}, {"value": 1000.0, "unit": "ml"}),
        ({"count": 1}, None),  # одна упаковка без веса — количество неизвестно
        ({"count": 1, "quantity": {"value": 180, "unit": "g"}}, {"value": 180.0, "unit": "g"}),
        ({"count": 0}, None),
        ({"count": 2.5}, None),
        ({}, None),
    ],
)
def test_products_quantity(item, expected):
    (product,) = parse_products(seen(("продукт", item)))
    assert (product.quantity.to_dict() if product.quantity else None) == expected


@pytest.mark.parametrize(
    "raw, staple",
    [("перец красный", "black_pepper"), ("масло оливковое", "sunflower_oil"), ("вода минеральная", "water")],
)
def test_fallback_skips_staples(catalog, index, raw, staple):
    (line,) = parse_response(answer(item(raw)), catalog, index)
    assert staple not in {c.code for c in line.candidates}
    assert line.status != "matched"


def test_cli_raw(tmp_path, capsys, monkeypatch):
    monkeypatch.chdir(tmp_path)
    photo = tmp_path / "p.jpg"
    photo.write_bytes(JPEG)
    fake = tmp_path / "a.json"
    fake.write_text('{"items": []}', encoding="utf-8")
    assert cli_main([str(photo), "--fake", str(fake), "--raw"]) == 0
    assert "сырой ответ модели" in capsys.readouterr().out


def test_no_candidates_and_nothing_found(catalog, index):
    (line,) = parse_response(answer(item("ПАКЕТ МАЙКА")), catalog, index)
    assert line.candidates == ()
    assert line.status == "unmatched"


def test_without_index_no_fallback(catalog):
    (line,) = parse_response(answer(item("молоко")), catalog)
    assert line.status == "unmatched"


@pytest.mark.parametrize(
    "cands, status",
    [
        ((("butter", 0.95),), "matched"),
        ((("butter", 0.85), ("sunflower_oil", 0.75)), "ambiguous"),  # мал отрыв
        ((("butter", 0.9), ("sunflower_oil", 0.6)), "matched"),
        ((("butter", 0.6),), "ambiguous"),  # мало уверенности
    ],
)
def test_status(catalog, index, cands, status):
    # «МАСЛО» похоже и на сливочное, и на подсолнечное — оба кандидата остаются
    (line,) = parse_response(answer(item("МАСЛО", *cands)), catalog, index)
    assert line.status == status


def test_candidates_cleaned(catalog, index):
    raw = {"raw_name": "сыр творог сметана макароны", "candidates": [
        {"code": "cheese", "confidence": 1.7},       # больше 1 → 1
        {"code": "cheese", "confidence": 0.2},       # дубль → берём максимум
        {"code": "butter", "confidence": "много"},  # не число → отбрасываем
        {"code": "milk", "confidence": float("nan")},
        {"code": "sour_cream", "confidence": 0.3},
        {"code": "cottage_cheese", "confidence": 0.4},
        {"code": "pasta", "confidence": 0.1},        # четвёртый → не влезает в топ-3
        "мусор",
    ]}
    (line,) = parse_response(json.dumps({"items": [raw]}), catalog, index)
    assert [(c.code, c.confidence) for c in line.candidates] == [
        ("cheese", 1.0), ("cottage_cheese", 0.4), ("sour_cream", 0.3),
    ]


@pytest.mark.parametrize(
    "quantity, expected",
    [
        ({"value": 0.532, "unit": "кг"}, {"value": 532.0, "unit": "g"}),
        ({"value": "0,5", "unit": "л"}, {"value": 500.0, "unit": "ml"}),
        ({"value": 200, "unit": "г."}, {"value": 200.0, "unit": "g"}),
        ({"value": 10, "unit": "шт"}, {"value": 10.0, "unit": "pcs"}),
        ({"value": 1.5, "unit": "pcs"}, None),   # полторы штуки — не доверяем
        ({"value": 0, "unit": "g"}, None),
        ({"value": -5, "unit": "g"}, None),
        ({"value": 5, "unit": "пачка"}, None),
        ({"value": 2_000_000, "unit": "g"}, None),
        ("500 г", None),
        (None, None),
    ],
)
def test_quantity(catalog, index, quantity, expected):
    (line,) = parse_response(answer(item("сыр", ("cheese", 0.9), quantity=quantity)), catalog, index)
    assert (line.suggested_quantity.to_dict() if line.suggested_quantity else None) == expected


def test_items_edge_cases(catalog, index):
    assert parse_response('{"items": []}', catalog, index) == []
    lines = parse_response('{"items": ["строка", 42, {"raw_name": "", "candidates": []}, {"raw_name": "  сыр\\n твёрдый  "}]}', catalog, index)
    assert len(lines) == 1 and lines[0].raw_name == "сыр твёрдый"
    (long,) = parse_response(answer(item("а" * 500, ("cheese", 0.9))), catalog, index)
    assert len(long.raw_name) == 200


@pytest.mark.parametrize("text", ['{"products": []}', '{"items": "много"}', "[1, 2]"])
def test_items_missing(catalog, index, text):
    with pytest.raises(RecognitionError):
        parse_response(text, catalog, index)


def test_to_dict_matches_contract(catalog, index):
    (line,) = parse_response(answer(item("ЯЙЦО", ("egg", 0.95))), catalog, index)
    assert line.to_dict() == {
        "line_id": "line-1",
        "raw_name": "ЯЙЦО",
        "candidates": [{"ingredient_id": "egg", "name": "Яйцо куриное", "confidence": 0.95}],
        "suggested_quantity": None,
        "status": "matched",
    }


# --- распознавание целиком --------------------------------------------------------------

def test_detect_mime():
    assert detect_mime(JPEG) == "image/jpeg"
    assert detect_mime(PNG) == "image/png"
    assert detect_mime(b"GIF89a...") is None


def test_recognize_end_to_end(catalog, index):
    provider = FakeProvider(answer(item("ЯЙЦО С1 10ШТ", ("egg", 0.95))))
    lines = recognize(PNG, "receipt", catalog, provider, index)
    assert lines[0].best.code == "egg"
    size, mime, prompt = provider.calls[0]
    assert (size, mime) == (len(PNG), "image/png")
    assert "кассового чека" in prompt


@pytest.mark.parametrize("image", [b"GIF89a" + b"\0" * 10, b"", b"\xff\xd8\xff" + b"\0" * MAX_IMAGE_BYTES])
def test_recognize_rejects_bad_images(catalog, image):
    provider = FakeProvider("{}")
    with pytest.raises(InvalidImage):
        recognize(image, "receipt", catalog, provider)
    assert provider.calls == []  # до провайдера не дошли


def test_recognize_wraps_provider_errors(catalog):
    def boom(*_):
        raise ConnectionError("нет сети")

    with pytest.raises(RecognitionError, match="нет сети"):
        recognize(JPEG, "products", catalog, FakeProvider(boom))


def test_recognize_unknown_kind(catalog):
    with pytest.raises(ValueError):
        recognize(JPEG, "menu", catalog, FakeProvider("{}"))  # type: ignore[arg-type]


# --- GigaChat без сети -----------------------------------------------------------------

def test_gigachat_requires_model(monkeypatch):
    monkeypatch.delenv("GIGACHAT_MODEL", raising=False)
    with pytest.raises(RecognitionError, match="GIGACHAT_MODEL"):
        GigaChatProvider()


def test_gigachat_model_from_env(monkeypatch):
    monkeypatch.setenv("GIGACHAT_MODEL", "GigaChat-Test")
    assert GigaChatProvider().model == "GigaChat-Test"


class _FakeSdkClient:
    """Имитация клиента SDK gigachat 0.2.x: UploadedFile отдаёт id в поле id_."""

    def __init__(self, reply):
        self.reply, self.payload, self.deleted = reply, None, []

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def upload_file(self, file, purpose):
        assert purpose == "general" and file[2] == "image/jpeg"
        return SimpleNamespace(id_="file-123")

    def chat(self, payload):
        self.payload = payload
        return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=self.reply))])

    def delete_file(self, file_id):
        self.deleted.append(file_id)


def test_gigachat_provider_flow(monkeypatch):
    sdk = _FakeSdkClient('{"items": []}')
    provider = GigaChatProvider(model="GigaChat-2-Max")
    monkeypatch.setattr(provider, "_client", lambda: sdk)
    assert provider.complete(JPEG, "image/jpeg", "промпт") == '{"items": []}'
    message = sdk.payload["messages"][0]
    assert message["attachments"] == ["file-123"] and message["content"] == "промпт"
    assert sdk.payload["model"] == "GigaChat-2-Max"
    assert sdk.deleted == ["file-123"]  # фото удалено после запроса


def test_gigachat_provider_deletes_file_on_error(monkeypatch):
    sdk = _FakeSdkClient("")

    def fail(payload):
        raise RuntimeError("503 Service Unavailable")

    sdk.chat = fail
    provider = GigaChatProvider(model="GigaChat-2-Max")
    monkeypatch.setattr(provider, "_client", lambda: sdk)
    with pytest.raises(RecognitionError, match="503"):
        provider.complete(JPEG, "image/jpeg", "промпт")
    assert sdk.deleted == ["file-123"]


def test_explain_ssl_error():
    from dishgraph.recognition.providers import explain

    msg = explain(ConnectionError("[SSL: CERTIFICATE_VERIFY_FAILED] self-signed certificate in certificate chain"))
    assert "GIGACHAT_CA_BUNDLE_FILE" in msg and "Минцифры" in msg
    assert "GIGACHAT_CREDENTIALS" in explain(RuntimeError("401 Unauthorized"))


def test_response_text_formats():
    old = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content="старый"))])
    new = SimpleNamespace(messages=[SimpleNamespace(content=[SimpleNamespace(text="новый")])])
    assert _response_text(old) == "старый"
    assert _response_text(new) == "новый"
    with pytest.raises(RecognitionError):
        _response_text(SimpleNamespace())


# --- CLI ------------------------------------------------------------------------------

def test_cli_with_fake_and_expected(tmp_path, capsys, monkeypatch):
    monkeypatch.chdir(tmp_path)  # чтобы не подхватить чужой .env
    photo = tmp_path / "check.jpg"
    photo.write_bytes(JPEG)
    fake = tmp_path / "answer.json"
    fake.write_text(answer(item("ЯЙЦО", ("egg", 0.95)), item("СЫР РОС.", ("cheese", 0.9))), encoding="utf-8")
    expected = tmp_path / "expected.json"
    expected.write_text(json.dumps({"check.jpg": ["egg", "milk"]}), encoding="utf-8")
    report = tmp_path / "report.json"

    assert cli_main([str(photo), "--fake", str(fake), "--expected", str(expected), "--report", str(report)]) == 0
    out = capsys.readouterr().out
    assert "верно: 1/2" in out and "пропущено: ['milk']" in out and "лишнее: ['cheese']" in out
    assert "точность 50%" in out and "полнота 50%" in out
    assert json.loads(report.read_text(encoding="utf-8"))["check.jpg"][0]["candidates"][0]["ingredient_id"] == "egg"
