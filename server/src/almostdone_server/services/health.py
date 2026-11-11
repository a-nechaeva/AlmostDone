from ..errors import APIError


def readiness(service):
    checks = {}
    try:
        service.store.check_health()
        checks['storage'] = 'ok'
    except Exception:
        checks['storage'] = 'unavailable'
    try:
        service.catalog.require_engine()
        checks['engine'] = 'ok'
    except Exception:
        checks['engine'] = 'unavailable'
    checks['catalog'] = 'ok' if service.catalog.ingredients and service.catalog.recipes else 'unavailable'
    checks['yandex'] = 'configured' if 'yandex' in service.auth_providers else 'disabled'
    checks['recognition'] = 'configured' if service.recognizer is not None else 'disabled'
    failed = [name for name, status in checks.items() if status == 'unavailable']
    if failed:
        raise APIError(503, 'service_unavailable', 'Required dependencies are unavailable',
                       details=[{'field': name, 'code': 'unavailable',
                                 'message': 'Dependency readiness check failed'} for name in failed])
    return {'status': 'ok', 'api_version': 'v1', 'checks': checks}
