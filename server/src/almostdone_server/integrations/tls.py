"""TLS for outgoing HTTPS (Yandex ID, recipe photos).

Python from python.org on macOS does not see the system certificates; certifi's bundle is used
when it is installed, otherwise the platform default.
"""
import ssl


def default_context() -> ssl.SSLContext:
    try:
        import certifi
    except ImportError:
        return ssl.create_default_context()
    return ssl.create_default_context(cafile=certifi.where())
