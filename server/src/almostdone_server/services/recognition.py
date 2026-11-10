"""Recognition application use cases; no HTTP request handling."""
import time
from uuid import uuid4

from ..errors import APIError, invalid
from .pagination import iso
from .ports import RecognitionFailure


class RecognitionService:
    def __init__(self, runtime, catalog, users, recognizer, validate_line):
        self.runtime, self.catalog, self.users = runtime, catalog, users
        self.recognizer, self.validate_line = recognizer, validate_line

    def execute(self, db, uid, user, session, oid, body, params):
        if oid == "recognitions_create":
            if self.recognizer is None:
                raise APIError(503, "service_unavailable", "Сервис распознавания ещё не подключён")
            failure = None
            try:
                items = self.recognizer.recognize(body["_image"], body["kind"])
            except RecognitionFailure:
                items = []
                failure = APIError(422, "recognition_failed", "Не удалось распознать изображение; попробуйте другое фото").body()
            except APIError as error:
                raise APIError(503, "service_unavailable", "Сервис распознавания недоступен") from None
            except Exception:
                raise APIError(503, "service_unavailable", "Сервис распознавания недоступен") from None
            if not isinstance(items, list) or len(items) > 100:
                raise APIError(503, "service_unavailable", "Некорректный результат распознавания")
            for item in items:
                try:
                    self.validate_line(item)
                except APIError:
                    raise APIError(503, "service_unavailable", "Некорректная позиция распознавания") from None
                for candidate in item["candidates"]:
                    if candidate["ingredient_id"] not in self.catalog.ingredients:
                        raise APIError(503, "service_unavailable", "Распознавание вернуло неизвестный ID")
            if len({i["line_id"] for i in items}) != len(items):
                raise APIError(503, "service_unavailable", "Распознавание вернуло повторяющиеся позиции")
            recognition = {"id": "pending", "kind": body["kind"], "status": "failed" if failure else "succeeded", "items": items,
                           "expires_at": iso(time.time() + 86400), "poll_after_seconds": 2, "failure": failure}
            rid = self.runtime.put_object(db, uid, "recognition", recognition, 86400)
            recognition["id"] = rid
            self.runtime.update_object(db, rid, recognition)
            return recognition
        if oid == "recognitions_status":
            recognition, _ = self.runtime.get_object(db, params["recognition_id"], uid, "recognition")
            return recognition
        if oid == "recognitions_import":
            rid = body["recognition_id"]
            previous = self.runtime.previous_import(db, rid)
            if previous and previous["user_id"] == uid:
                raise APIError(409, "already_imported", "Результат уже импортирован")
            recognition, _ = self.runtime.get_object(db, rid, uid, "recognition")
            if recognition["kind"] != body["kind"] or recognition["status"] != "succeeded":
                raise invalid("Тип или состояние задачи не соответствует импорту", "recognition_id")
            ids = [i["line_id"] for i in body["items"]]
            if len(ids) != len(set(ids)) or set(ids) - {i["line_id"] for i in recognition["items"]}:
                raise invalid("Позиция повторяется или не принадлежит задаче", "items")
            for item in body["items"]:
                self.users.add(user, item["ingredient_id"], item["quantity"])
            operation_id = str(uuid4())
            self.runtime.record_import(db, rid, uid, operation_id)
            return {"operation_id": operation_id, "recognition_id": rid,
                    "state_version": user["version"], "pantry": self.users.pantry(user)["items"]}
        raise ValueError(f"Unsupported operation: {oid}")
