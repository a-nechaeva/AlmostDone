"""Прогон распознавания на своих фото.

    python -m dishgraph.recognition.cli --list-models
    python -m dishgraph.recognition.cli photos/check1.jpg photos/check2.png --kind receipt
    python -m dishgraph.recognition.cli photos/*.jpg --kind products --expected expected.json --report report.json
    python -m dishgraph.recognition.cli photo.jpg --fake answer.json      # без сети: готовый ответ модели
    python -m dishgraph.recognition.cli --show-prompt --kind receipt       # посмотреть промпт

expected.json — какие продукты на самом деле на фото, для подсчёта качества:
    {"check1.jpg": ["egg", "milk", "cheese"], "fridge.jpg": ["butter"]}

Ключ и модель — в переменных окружения или в файле .env рядом (см. providers.py). .env не коммитим.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from ..loader import load_catalog
from ..search import SearchIndex
from .models import RecognitionError
from .prompt import build_prompt
from .providers import FakeProvider, GigaChatProvider, VisionProvider
from .service import recognize


def load_dotenv(path: Path) -> None:
    """KEY=VALUE из .env в окружение, не перезаписывая уже заданные переменные."""
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("'\""))


class _PrintRaw:
    """Обёртка провайдера: печатает сырой ответ модели перед разбором."""

    def __init__(self, provider: VisionProvider) -> None:
        self._provider = provider

    @staticmethod
    def _show(title: str, text: str) -> str:
        print(f"  --- {title} ---")
        print("  " + text.strip().replace("\n", "\n  "))
        print("  " + "-" * (len(title) + 8))
        return text

    def complete(self, image: bytes, mime: str, prompt: str) -> str:
        return self._show("сырой ответ модели", self._provider.complete(image, mime, prompt))

    def complete_text(self, prompt: str) -> str:
        complete_text = getattr(self._provider, "complete_text", None)
        if complete_text is None:
            raise RecognitionError("Провайдер не умеет текстовые запросы")
        return self._show("сырой ответ на сопоставление", complete_text(prompt))


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Распознавание продуктов по фото")
    p.add_argument("photos", nargs="*", type=Path)
    p.add_argument("--kind", choices=["receipt", "products"], default="receipt")
    p.add_argument("--catalog", type=Path, help="JSON каталога (по умолчанию data/fixtures.json)")
    p.add_argument("--fake", type=Path, help="файл с готовым ответом модели вместо GigaChat")
    p.add_argument("--expected", type=Path, help="JSON {фото: [коды]} для подсчёта качества")
    p.add_argument("--report", type=Path, help="сохранить результат в JSON")
    p.add_argument("--list-models", action="store_true", help="модели, доступные ключу GigaChat")
    p.add_argument("--show-prompt", action="store_true")
    p.add_argument("--raw", action="store_true", help="показать сырой ответ модели (если результат пустой или странный)")
    args = p.parse_args(argv)

    load_dotenv(Path.cwd() / ".env")
    catalog = load_catalog(args.catalog) if args.catalog else load_catalog()

    if args.show_prompt:
        print(build_prompt(args.kind, catalog))
        return 0
    try:
        if args.list_models:
            for name in GigaChatProvider.list_models():
                print(name)
            return 0
        if not args.photos:
            p.error("укажите хотя бы одно фото")
        provider = FakeProvider(args.fake.read_text(encoding="utf-8")) if args.fake else GigaChatProvider()
    except RecognitionError as e:
        print(f"ошибка: {e}", file=sys.stderr)
        return 1
    if args.raw:
        provider = _PrintRaw(provider)
    index = SearchIndex(catalog)
    expected = json.loads(args.expected.read_text(encoding="utf-8")) if args.expected else {}

    report: dict[str, object] = {}
    tp = fp = fn = 0
    for photo in args.photos:
        print(f"\n=== {photo.name}")
        try:
            lines = recognize(photo.read_bytes(), args.kind, catalog, provider, index)
        except RecognitionError as e:
            print(f"  ошибка: {e}")
            report[photo.name] = {"error": str(e)}
            continue
        for line in lines:
            best = line.best
            target = f"{best.name} [{best.code}] {best.confidence:.2f}" if best else "—"
            qty = f"  {line.suggested_quantity.value:g} {line.suggested_quantity.unit}" if line.suggested_quantity else ""
            print(f"  {line.status:9}  {line.raw_name[:40]:40} → {target}{qty}")
        report[photo.name] = [line.to_dict() for line in lines]

        if photo.name in expected:
            want = set(expected[photo.name])
            got = {line.best.code for line in lines if line.best}
            tp += len(want & got)
            fp += len(got - want)
            fn += len(want - got)
            print(f"  верно: {len(want & got)}/{len(want)}; лишнее: {sorted(got - want) or '—'}; пропущено: {sorted(want - got) or '—'}")

    if expected and tp + fp + fn:
        precision = tp / (tp + fp) if tp + fp else 0.0
        recall = tp / (tp + fn) if tp + fn else 0.0
        print(f"\nИтого: точность {precision:.0%} (сколько найденного верно), полнота {recall:.0%} (сколько нужного найдено)")
    if args.report:
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\nОтчёт: {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
