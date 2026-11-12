"""Coordinate use cases, transaction boundaries and retry protection."""
import copy
import hashlib
import json
from dataclasses import asdict

from ..errors import APIError, invalid
from .auth import AuthService
from .catalog import CatalogService
from .commands import Command, Result, MUTATIONS, RETRYABLE_COMMANDS
from .pagination import Pagination
from .ports import Repository
from .recognition import RecognitionService
from .recommendations import RecommendationService
from .users import UserService
from .runtime import RuntimeService
from .state import UserStateService
from .health import readiness
from .dietary import DietaryService


class ApplicationService:
    def __init__(self, store: Repository, catalog, auth_providers, recognizer, validate_recognition_line):
        self.store, self.catalog = store, catalog
        self.runtime = RuntimeService(store)
        self.states = UserStateService(store, catalog)
        pagination = Pagination(self.runtime, catalog)
        self.auth = AuthService(store, auth_providers or {}, self.states)
        self.dietary = DietaryService(store)
        self.users = UserService(catalog, pagination, self.dietary)
        self.catalogue = CatalogService(catalog, pagination, self.dietary)
        self.recommendations = RecommendationService(self.runtime, catalog, pagination)
        self.recognition = RecognitionService(self.runtime, catalog, self.users, recognizer, validate_recognition_line)

    @property
    def auth_providers(self):
        return self.auth.providers

    @property
    def recognizer(self):
        return self.recognition.recognizer

    @recognizer.setter
    def recognizer(self, value):
        self.recognition.recognizer = value

    def execute(self, command: Command, validate_result=lambda result: None) -> Result:
        """Validate the result before committing mutations or recording a replay."""
        oid, body, params = command.operation, command.payload, command.parameters
        if oid == "health_get":
            result = Result({"status": "ok", "api_version": "v1"})
            validate_result(result)
            return result
        if oid == "readiness_get":
            result = Result(readiness(self))
            validate_result(result)
            return result
        if oid == "auth_yandex":
            return self.auth.login(oid[5:], body, validate_result)
        if oid == "auth_refresh":
            return self.auth.refresh(body["refresh_token"], validate_result)

        with self.store.transaction() as db:
            session = self.auth.authenticate(db, command.access_token)
            uid = session["user_id"]
            user = self.states.load(db, uid)
            self.auth.authenticate(db, command.access_token)
            fingerprint = None
            if oid in RETRYABLE_COMMANDS:
                if not command.idempotency_key:
                    raise invalid("Требуется ключ повторной операции", "idempotency_key")
                fingerprint = self.fingerprint(body)
                replay = self.runtime.replay(db, uid, oid, command.idempotency_key, fingerprint)
                if replay is not None:
                    result = Result(**replay)
                    validate_result(result)
                    return result
            if oid in MUTATIONS:
                if command.expected_version is None:
                    raise APIError(428, "precondition_required", "Требуется версия состояния")
                if command.expected_version != user["version"]:
                    raise APIError(412, "state_conflict", "Состояние изменилось; перечитайте данные")
            before = copy.deepcopy(user)
            if oid == "auth_logout":
                self.auth.revoke_family(db, session["family"])
                data = None
            else:
                service = self.use_case(oid)
                execution_user = user
                if oid in ('recipes_get', 'recommendations_create', 'recommendations_page',
                           'recommendations_graph', 'purchases_budget', 'purchases_single_purchase',
                           'favorites_recipes'):
                    execution_user = {**user, '_dietary': self.dietary.context(db, uid)}
                data = service.execute(db, uid, execution_user, session, oid, body, params)
            if oid in MUTATIONS and user != before:
                user["version"] += 1
                self.states.save(db, uid, user)
                data["state_version"] = user["version"]
            result = Result(data, user["version"])
            validate_result(result)
            if oid in RETRYABLE_COMMANDS:
                self.runtime.record(db, uid, oid, command.idempotency_key, fingerprint, asdict(result))
            return result

    def purge(self):
        with self.store.transaction() as db:
            self.runtime.purge(db)
            self.auth.purge(db)

    def use_case(self, operation):
        if operation.startswith(("recommendations_", "purchases_")):
            return self.recommendations
        if operation.startswith("recognitions_"):
            return self.recognition
        if operation.startswith("catalog_") or operation == "recipes_get":
            return self.catalogue
        if operation.startswith(("profile_", "pantry_", "favorites_")) or operation == "state_get":
            return self.users
        raise APIError(503, "service_unavailable", "Операция ещё не подключена")

    @staticmethod
    def fingerprint(body):
        if "_image" in body:
            return hashlib.sha256(body["kind"].encode() + b"\0" + body["mime"].encode() + b"\0" + body["_image"]).hexdigest()
        return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()
