"""VK ID authorization-code/PKCE exchange, following the official VK ID SDK."""
import json
import secrets
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, build_opener

from .yandex import _NoRedirect
from ..errors import APIError


class VkProvider:
    TOKEN_URL = "https://id.vk.ru/oauth2/auth"
    USER_URL = "https://id.vk.ru/oauth2/user_info"

    def __init__(self, client_id, redirect_uri, request=None):
        if not client_id or not redirect_uri:
            raise ValueError("VK client_id and redirect_uri must be configured")
        self.client_id, self.redirect_uri = str(client_id), redirect_uri
        self.request = request or self.post

    @staticmethod
    def rejected():
        return APIError(401, "invalid_credentials", "Вход через VK ID не подтверждён",
                        headers={"WWW-Authenticate": "Bearer"})

    @staticmethod
    def post(url, fields):
        request = Request(url, data=urlencode(fields).encode(), headers={
            "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"})
        try:
            with build_opener(_NoRedirect()).open(request, timeout=10) as response:
                content = response.read(65537)
                if len(content) > 65536:
                    raise ValueError("Oversized VK response")
                result = json.loads(content)
        except HTTPError as error:
            status = error.code
            error.close()
            if status in (400, 401, 403):
                raise VkProvider.rejected() from None
            raise APIError(503, "service_unavailable", "VK ID временно недоступен") from None
        except (URLError, OSError, ValueError):
            raise APIError(503, "service_unavailable", "Не удалось проверить вход через VK ID") from None
        if not isinstance(result, dict):
            raise APIError(503, "service_unavailable", "Некорректный ответ VK ID")
        if result.get("error"):
            if result["error"] in ("invalid_grant", "invalid_token", "invalid_request", "access_denied"):
                raise VkProvider.rejected()
            raise APIError(503, "service_unavailable", "Не удалось проверить вход через VK ID")
        return result

    def exchange(self, payload):
        if payload["redirect_uri"] != self.redirect_uri:
            raise self.rejected()
        state = secrets.token_urlsafe(32)
        token = self.request(self.TOKEN_URL, {"grant_type": "authorization_code", "client_id": self.client_id,
            "redirect_uri": self.redirect_uri, "code": payload["authorization_code"],
            "device_id": payload["device_id"], "code_verifier": payload["code_verifier"], "state": state})
        access = token.get("access_token")
        if not isinstance(access, str) or not access or token.get("state") != state:
            raise self.rejected()
        identity = self.request(self.USER_URL, {"client_id": self.client_id, "access_token": access})
        user = identity.get("user", {})
        subject = user.get("user_id") if isinstance(user, dict) else None
        if isinstance(subject, bool) or not isinstance(subject, (str, int)) or not str(subject):
            raise self.rejected()
        token_subject = token.get("user_id")
        if token_subject is not None and str(token_subject) != str(subject):
            raise self.rejected()
        return str(subject)
