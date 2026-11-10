from uuid import uuid4


class StorageError(Exception):
    """Persistence failure without HTTP status, headers or response formatting."""


class StorageUnavailable(StorageError):
    pass


class StorageSchemaError(StorageError):
    pass


class StorageConflict(StorageError):
    pass


class StorageValueError(StorageError):
    def __init__(self, message, field):
        super().__init__(message)
        self.field = field


class APIError(Exception):
    def __init__(self, status, code, message, *, details=None, headers=None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.details = details or []
        self.headers = headers or {}

    def body(self, request_id=None):
        return {"error": {"code": self.code, "message": self.message,
                          "retryable": self.status in (429, 503),
                          "request_id": request_id or str(uuid4()), "details": self.details}}


def invalid(message, field="", code="invalid_value"):
    return APIError(422, "validation_error", message,
                    details=[{"field": field, "code": code, "message": message}])

