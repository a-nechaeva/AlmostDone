"""Yandex userinfo verification. Credentials are never accepted as app sessions."""
import json
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener

from ..errors import APIError


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # The OAuth token belongs only to the fixed Yandex userinfo endpoint.
        return None


class YandexProvider:
    def __init__(self, client_id, userinfo=None):
        if not client_id:
            raise ValueError("Yandex client_id must be configured")
        self.client_id = client_id
        self.userinfo = userinfo or self.fetch_userinfo

    @staticmethod
    def fetch_userinfo(token):
        request = Request('https://login.yandex.ru/info?format=json',
                          headers={'Authorization': 'OAuth ' + token, 'Accept': 'application/json'})
        try:
            with build_opener(_NoRedirect()).open(request, timeout=10) as response:
                content = response.read(65537)
                if len(content) > 65536:
                    raise ValueError('Unexpected userinfo response size')
                return json.loads(content)
        except HTTPError as error:
            status = error.code
            error.close()
            if status in (400, 401, 403):
                raise APIError(401, 'invalid_credentials', 'Вход через Яндекс не подтверждён',
                               headers={'WWW-Authenticate': 'Bearer'}) from None
            raise APIError(503, 'service_unavailable', 'Яндекс ID временно недоступен') from None
        except (URLError, TimeoutError, OSError, ValueError):
            raise APIError(503, 'service_unavailable', 'Не удалось проверить токен Яндекс ID') from None

    def exchange(self, payload):
        token = payload['oauth_token']
        # Prevent malformed tokens becoming HTTP header injection or an internal error.
        if not token.isascii() or any(ord(char) < 33 or ord(char) == 127 for char in token):
            raise APIError(401, 'invalid_credentials', 'Некорректный токен Яндекс ID',
                           headers={'WWW-Authenticate': 'Bearer'})
        identity = self.userinfo(token)
        if (not isinstance(identity, dict) or identity.get('client_id') != self.client_id
                or not isinstance(identity.get('id'), str) or not identity['id']):
            raise APIError(401, 'invalid_credentials', 'Токен не принадлежит настроенному приложению',
                           headers={'WWW-Authenticate': 'Bearer'})
        return identity['id']
