"""Bounded multipart parsing and image validation at the HTTP boundary."""
import io
import warnings

from PIL import Image, UnidentifiedImageError
from starlette.exceptions import HTTPException
from ..errors import APIError, invalid

MAX_IMAGE = 10 * 1024 * 1024


async def image_body(request, contract, oid):
    # Bound the complete multipart body before the multipart parser can spool unbounded data.
    chunks, size = [], 0
    async for chunk in request.stream():
        size += len(chunk)
        if size > MAX_IMAGE + 65536:
            raise APIError(413, "file_too_large", "Изображение превышает 10 MiB")
        chunks.append(chunk)
    request._body = b"".join(chunks)
    try:
        form = await request.form(max_files=1, max_fields=1, max_part_size=MAX_IMAGE)
    except HTTPException:
        raise invalid("Ожидаются multipart-поля kind и file") from None
    try:
        keys = [key for key, _ in form.multi_items()]
        if sorted(keys) != ["file", "kind"]:
            raise invalid("Нужны ровно два поля: kind и file")
        upload = form["file"]
        if not hasattr(upload, "read"):
            raise invalid("file должен содержать изображение", "file")
        contract.body(oid, {"kind": form["kind"], "file": "binary"}, "multipart/form-data")
        image = await upload.read(MAX_IMAGE + 1)
        if len(image) > MAX_IMAGE:
            raise APIError(413, "file_too_large", "Изображение превышает 10 MiB")
        mime = upload.content_type
        if mime not in ("image/jpeg", "image/png"):
            raise APIError(415, "unsupported_media_type", "Разрешены JPEG и PNG")
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", Image.DecompressionBombWarning)
                with Image.open(io.BytesIO(image)) as decoded:
                    if decoded.format not in ("JPEG", "PNG") or Image.MIME[decoded.format] != mime:
                        raise APIError(415, "unsupported_media_type", "MIME не соответствует изображению")
                    if decoded.width * decoded.height > 25_000_000:
                        raise invalid("Изображение превышает 25 мегапикселей", "file")
                    decoded.verify()
        except (UnidentifiedImageError, OSError, Image.DecompressionBombError, Image.DecompressionBombWarning):
            raise APIError(415, "unsupported_media_type", "Изображение повреждено или не поддерживается") from None
        return {"kind": form["kind"], "_image": image, "mime": mime}
    finally:
        await form.close()
