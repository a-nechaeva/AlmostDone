"""Provider verification, session issuance, expiry, rotation and revocation."""
import hashlib
import json
import secrets
import time
from uuid import uuid4

from ..errors import APIError
from .commands import Result
from .ports import AuthProvider, Repository
from .state import UserStateService


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class AuthService:
    def __init__(self, store: Repository, providers: dict[str, AuthProvider], states=None):
        self.store, self.providers, self.records = store, providers, store.runtime
        self.states = states or UserStateService(store)

    def identity_user(self, db, provider, subject):
        fingerprint = digest(json.dumps([provider, subject], ensure_ascii=False))
        login, marker = "oauth_" + fingerprint[:26], "!oauth-only:" + fingerprint
        if self.store.persistent:
            return self.store.oauth_identity(db, provider, subject, login, marker)
        row = self.store.identity(db, login, marker)
        if row["password_hash"] != marker:
            raise APIError(409, "context_changed", "Логин занят другой учётной записью")
        return str(row["id"])

    def issue(self, db, user_id, family=None, refresh_until=None):
        self.states.load(db, user_id)
        now = time.time()
        until = now + 30 * 86400 if refresh_until is None else refresh_until
        access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(48)
        self.records.put(db.runtime, "sessions", digest(access), {
            "refresh_hash": digest(refresh), "user_id": user_id, "family": family or str(uuid4()),
            "access_until": now + 900, "refresh_until": until, "used": False, "revoked": False,
        })
        return {"user_id": user_id, "access_token": access, "refresh_token": refresh,
                "token_type": "Bearer", "expires_in": 900,
                "refresh_expires_in": max(1, int(until - now))}

    def authenticate(self, db, token):
        row = self.records.get(db.runtime, "sessions", digest(token))
        if row is None or row["revoked"] or row["access_until"] <= time.time():
            raise APIError(401, "session_expired", "Требуется действующая сессия")
        return row

    def revoke_family(self, db, family):
        self.records.revoke_family(db.runtime, family)

    def login(self, provider_name, payload, validate_result):
        provider = self.providers.get(provider_name)
        if provider is None:
            raise APIError(503, "service_unavailable", "OAuth-провайдер ещё не подключён")
        try:
            subject = provider.exchange(payload)
        except APIError:
            raise
        except Exception:
            raise APIError(503, "service_unavailable", "Провайдер входа недоступен") from None
        if not isinstance(subject, str) or not subject:
            raise APIError(401, "invalid_credentials", "Вход не подтверждён")
        with self.store.transaction() as db:
            user_id = self.identity_user(db, provider_name, subject)
            result = Result(self.issue(db, user_id))
            validate_result(result)
            return result

    def refresh(self, token, validate_result):
        result = None
        with self.store.transaction() as db:
            found = self.records.session_by_refresh(db.runtime, digest(token))
            if found:
                # Serialize refresh, logout and mutations on the same user lock.
                # Re-read AFTER acquiring it: another worker may have rotated or
                # revoked the token while this request was waiting.
                self.states.load(db, found[1]["user_id"])
                found = self.records.session_by_refresh(db.runtime, digest(token))
            if found:
                key, row = found
                if row["used"]:
                    # Commit the security revocation before reporting reuse.
                    self.revoke_family(db, row["family"])
                elif not row["revoked"] and row["refresh_until"] > time.time():
                    self.states.load(db, row["user_id"])
                    row["used"] = row["revoked"] = True
                    self.records.put(db.runtime, "sessions", key, row)
                    result = Result(self.issue(db, row["user_id"], row["family"], row["refresh_until"]))
                    validate_result(result)  # Failure rolls back old and new session records.
        if result is None:
            raise APIError(401, "session_expired", "Refresh token недействителен")
        return result

    def purge(self, db):
        now = time.time()
        if self.store.persistent:
            self.records.purge_sessions(db.runtime, now)
            return
        for key, row in self.records.items(db.runtime, "sessions"):
            if row["access_until"] <= now and row["refresh_until"] <= now:
                self.records.delete(db.runtime, "sessions", key)
