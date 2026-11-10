"""Мультимодальные LLM-провайдеры: картинка + промпт → текст ответа.

Провайдер сменный: логика распознавания от него не зависит. Для тестов — FakeProvider (без сети),
для работы — GigaChatProvider (официальный SDK `gigachat`, ставится отдельно: pip install -e '.[llm]').

Настройки GigaChat — переменные окружения (их читает и сам SDK):
  GIGACHAT_CREDENTIALS     ключ авторизации из личного кабинета (обязательно)
  GIGACHAT_MODEL           модель с поддержкой изображений (обязательно; список — cli --list-models)
  GIGACHAT_SCOPE           GIGACHAT_API_PERS для физлиц (по умолчанию в SDK)
  GIGACHAT_CA_BUNDLE_FILE  путь к корневому сертификату НУЦ Минцифры — если запросы падают на SSL
  GIGACHAT_VERIFY_SSL_CERTS=False  — только для локальной отладки, не для сервера
"""

from __future__ import annotations

import io
import os
from collections.abc import Callable
from typing import Any, Protocol

from .models import RecognitionError

_EXT = {"image/jpeg": "jpg", "image/png": "png"}


class VisionProvider(Protocol):
    def complete(self, image: bytes, mime: str, prompt: str) -> str:
        """Отправить изображение и промпт, вернуть текст ответа модели."""
        ...

    def complete_text(self, prompt: str) -> str:
        """Текстовый запрос без картинки (сопоставление названий с каталогом).

        Необязательный: если у провайдера его нет, сопоставление делает наш поиск.
        """
        ...


class FakeProvider:
    """Отдаёт заранее заданные ответы. Для тестов и демо без сети.

    response — один ответ на все запросы, список ответов по очереди (для фото продуктов запросов
    два: картинка и сопоставление) или функция (картинка | None, mime | None, промпт) -> ответ.
    """

    def __init__(self, response: str | list[str] | Callable[[bytes | None, str | None, str], str]) -> None:
        self._response = response
        self._queue = list(response) if isinstance(response, list) else None
        self.calls: list[tuple[int, str | None, str]] = []  # (размер картинки или 0, mime, промпт)

    def _answer(self, image: bytes | None, mime: str | None, prompt: str) -> str:
        self.calls.append((len(image) if image else 0, mime, prompt))
        if self._queue is not None:
            if not self._queue:
                raise RecognitionError("FakeProvider: ответы закончились")
            return self._queue.pop(0)
        if callable(self._response):
            return self._response(image, mime, prompt)
        return self._response  # type: ignore[return-value]

    def complete(self, image: bytes, mime: str, prompt: str) -> str:
        return self._answer(image, mime, prompt)

    def complete_text(self, prompt: str) -> str:
        return self._answer(None, None, prompt)


def _response_text(response: Any) -> str:
    """Текст ответа из объекта SDK (поддерживает старый и новый формат ответа)."""
    try:
        return response.choices[0].message.content
    except (AttributeError, IndexError, TypeError):
        pass
    try:
        return response.messages[0].content[0].text
    except (AttributeError, IndexError, TypeError):
        pass
    raise RecognitionError("Неожиданный формат ответа GigaChat")


def _file_id(uploaded: Any) -> str:
    """id загруженного файла: в SDK поле называется id_ (pydantic-алиас для id)."""
    file_id = getattr(uploaded, "id_", None) or getattr(uploaded, "id", None)
    if not file_id:
        raise RecognitionError("GigaChat не вернул id загруженного файла")
    return str(file_id)


SSL_HINT = (
    "GigaChat использует сертификат НУЦ Минцифры (Russian Trusted Root CA), которому Python не доверяет. "
    "Скачайте корневой сертификат и укажите путь в GIGACHAT_CA_BUNDLE_FILE (см. engine/README.md, «Настройка GigaChat»)."
)


def explain(error: Exception) -> str:
    """Понятное сообщение об ошибке GigaChat вместо трейсбека."""
    text = str(error)
    if "CERTIFICATE_VERIFY_FAILED" in text:
        return f"Ошибка SSL: {text}. {SSL_HINT}"
    if "401" in text or "Unauthorized" in text:
        return f"Ошибка авторизации: {text}. Проверьте GIGACHAT_CREDENTIALS и GIGACHAT_SCOPE."
    return f"Ошибка GigaChat: {text}"


class GigaChatProvider:
    def __init__(self, model: str | None = None, *, temperature: float = 0.1, timeout: float = 90.0, **client_kwargs: Any):
        self.model = model or os.environ.get("GIGACHAT_MODEL")
        if not self.model:
            raise RecognitionError(
                "Не задана модель: укажите GIGACHAT_MODEL (список моделей: python -m dishgraph.recognition.cli --list-models)"
            )
        self.temperature = temperature
        self._client_kwargs = {"timeout": timeout, **client_kwargs}

    def _client(self) -> Any:
        try:
            from gigachat import GigaChat
        except ImportError as e:
            raise RecognitionError("Не установлен SDK: pip install -e '.[llm]'") from e
        return GigaChat(**self._client_kwargs)

    def complete(self, image: bytes, mime: str, prompt: str) -> str:
        try:
            return self._complete(image, mime, prompt)
        except RecognitionError:
            raise
        except Exception as e:  # сеть, SSL, авторизация, лимиты
            raise RecognitionError(explain(e)) from e

    def complete_text(self, prompt: str) -> str:
        try:
            with self._client() as client:
                response = client.chat(
                    {
                        "model": self.model,
                        "temperature": self.temperature,
                        "messages": [{"role": "user", "content": prompt}],
                    }
                )
                return _response_text(response)
        except RecognitionError:
            raise
        except Exception as e:
            raise RecognitionError(explain(e)) from e

    def _complete(self, image: bytes, mime: str, prompt: str) -> str:
        with self._client() as client:
            uploaded = client.upload_file((f"image.{_EXT.get(mime, 'jpg')}", io.BytesIO(image), mime), purpose="general")
            file_id = _file_id(uploaded)
            try:
                response = client.chat(
                    {
                        "model": self.model,
                        "temperature": self.temperature,
                        "messages": [{"role": "user", "content": prompt, "attachments": [file_id]}],
                    }
                )
                return _response_text(response)
            finally:
                # фото чеков не храним у провайдера дольше запроса
                delete = getattr(client, "delete_file", None)
                if delete is not None:
                    try:
                        delete(file_id)
                    except Exception:
                        pass

    @staticmethod
    def list_models(**client_kwargs: Any) -> list[str]:
        try:
            from gigachat import GigaChat
        except ImportError as e:
            raise RecognitionError("Не установлен SDK: pip install -e '.[llm]'") from e
        try:
            with GigaChat(**client_kwargs) as client:
                return [getattr(m, "id_", None) or getattr(m, "id", "?") for m in client.get_models().data]
        except Exception as e:
            raise RecognitionError(explain(e)) from e
