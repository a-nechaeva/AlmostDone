"""Map dishgraph recognition results and failures to the application interface."""
from types import SimpleNamespace

from ..errors import APIError
from ..services.ports import RecognitionFailure


class EngineRecognizer:
    """Connect dishgraph.recognition module to the REST Recognizer interface."""
    def __init__(self, gateway, provider, *, catalog=None):
        self.gateway, self.provider = gateway, provider
        self.catalog = catalog

    def recognize(self, image, kind):
        from dishgraph.recognition import InvalidImage, RecognitionError, recognize

        failed_request = [False]

        def guarded(method):
            def call(*args):
                try:
                    return method(*args)
                except Exception:
                    failed_request[0] = True
                    raise
            return call

        provider = SimpleNamespace(complete=guarded(self.provider.complete))
        if callable(getattr(self.provider, "complete_text", None)):
            provider.complete_text = guarded(self.provider.complete_text)
        try:
            gateway = self.catalog.gateway if self.catalog is not None else self.gateway
            lines = recognize(image, kind, gateway.lookup_catalog, provider, gateway.search_index)
        except InvalidImage:
            raise APIError(415, "unsupported_media_type", "Изображение не поддерживается") from None
        except RecognitionError:
            if failed_request[0]:
                raise APIError(503, "service_unavailable", "Провайдер распознавания временно недоступен") from None
            raise RecognitionFailure() from None
        return [line.to_dict() for line in lines]
