"""Фото рецептов через наш сервер.

Сайт с фото стоит за Cloudflare, и из некоторых сетей (мобильный интернет, Wi-Fi в вузе) телефон
до него не достаёт: соединение открывается, но данные не идут. Ноутбук с сервером скачивает фото
один раз, кладёт во временную папку и отдаёт телефону тем же путём, что и каталог (в том числе
через `adb reverse`).
"""

from __future__ import annotations

import hashlib
import tempfile
import urllib.request
from pathlib import Path

from .tls import default_context

MAX_BYTES = 8 * 1024 * 1024
TIMEOUT = 20
CACHE_DIR = Path(tempfile.gettempdir()) / "almostdone-recipe-photos"


class PhotoUnavailable(Exception):
    """Фото не скачалось (сеть, не картинка, слишком большое)."""


def media_type(data: bytes) -> str | None:
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


def download(url: str) -> bytes:
    """Скачать фото по ссылке из каталога. Подменяется в тестах."""
    request = urllib.request.Request(url, headers={"User-Agent": "AlmostDone-server"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT, context=default_context()) as response:  # noqa: S310 — ссылки только из каталога
            data = response.read(MAX_BYTES + 1)
    except Exception as e:  # noqa: BLE001 — любая сетевая ошибка → «фото недоступно»
        raise PhotoUnavailable(str(e)) from e
    if len(data) > MAX_BYTES:
        raise PhotoUnavailable("слишком большое фото")
    return data


def fetch(url: str, cache_dir: Path | None = None) -> tuple[bytes, str]:
    """(байты, MIME) — из кэша на диске или скачав один раз."""
    cache_dir = cache_dir or CACHE_DIR
    path = cache_dir / hashlib.sha256(url.encode()).hexdigest()
    if path.is_file():
        data = path.read_bytes()
    else:
        data = download(url)
        if media_type(data) is None:
            raise PhotoUnavailable("по ссылке не картинка")
        cache_dir.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(data)
        tmp.replace(path)
    kind = media_type(data)
    if kind is None:
        raise PhotoUnavailable("по ссылке не картинка")
    return data, kind
