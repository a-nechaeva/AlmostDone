"""Распознавание продуктов по фото чека или фото продуктов через мультимодальную LLM.

    from dishgraph import load_catalog, SearchIndex
    from dishgraph.recognition import GigaChatProvider, recognize

    catalog = load_catalog()
    index = SearchIndex(catalog)          # тот же индекс, что для автодополнения
    provider = GigaChatProvider()         # настройки из переменных окружения GIGACHAT_*
    lines = recognize(image_bytes, "receipt", catalog, provider, index)
    [line.to_dict() for line in lines]    # RecognitionLine из контракта API
"""

from .models import (
    ALLOWED_MIME,
    MAX_IMAGE_BYTES,
    Candidate,
    InvalidImage,
    Quantity,
    RecognitionError,
    RecognitionKind,
    RecognitionLine,
)
from .parse import SeenProduct, build_product_lines, extract_json, parse_mapping, parse_products, parse_response
from .prompt import build_mapping_prompt, build_products_prompt, build_prompt, build_receipt_prompt
from .providers import FakeProvider, GigaChatProvider, VisionProvider
from .service import detect_mime, recognize

__all__ = [
    "ALLOWED_MIME",
    "MAX_IMAGE_BYTES",
    "Candidate",
    "FakeProvider",
    "GigaChatProvider",
    "InvalidImage",
    "Quantity",
    "RecognitionError",
    "RecognitionKind",
    "RecognitionLine",
    "SeenProduct",
    "VisionProvider",
    "build_mapping_prompt",
    "build_product_lines",
    "build_products_prompt",
    "build_prompt",
    "build_receipt_prompt",
    "detect_mime",
    "extract_json",
    "parse_mapping",
    "parse_products",
    "parse_response",
    "recognize",
]
