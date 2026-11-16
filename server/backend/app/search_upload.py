"""Bound the multipart body while reading it, including requests without a length."""
import asyncio
from python_multipart.exceptions import MultipartParseError

from fastapi import HTTPException, Request
from starlette.datastructures import UploadFile
from starlette.formparsers import MultiPartException, MultiPartParser

from .config import MAX_UPLOAD_BYTES


class SearchBodyTooLarge(MultiPartException):
    pass


async def read_search_photo(request: Request) -> tuple[bytes, str]:
    max_body = MAX_UPLOAD_BYTES + 64 * 1024
    length = request.headers.get('content-length')
    if length is not None:
        try:
            size = int(length)
        except ValueError:
            raise HTTPException(400, 'Некорректный размер запроса') from None
        if size > max_body:
            raise HTTPException(413, 'Максимальный размер фото — 8 МБ')
    if request.headers.get('content-type', '').split(';')[0].strip().lower() != 'multipart/form-data':
        raise HTTPException(422, 'Отправьте фотографию в поле file')

    async def chunks():
        total = 0
        async for block in request.stream():
            total += len(block)
            if total > max_body:
                raise SearchBodyTooLarge('Максимальный размер фото — 8 МБ')
            yield block

    try:
        async with asyncio.timeout(30):
            form = await MultiPartParser(request.headers, chunks(), max_files=1, max_fields=1).parse()
    except SearchBodyTooLarge as exc:
        raise HTTPException(413, exc.message) from exc
    except TimeoutError as exc:
        raise HTTPException(408, 'Истекло время загрузки фотографии') from exc
    except (MultiPartException, MultipartParseError) as exc:
        raise HTTPException(422, 'Некорректная форма загрузки') from exc
    try:
        photo = form.get('file')
        crop = form.get('crop', '')
        if not isinstance(photo, UploadFile) or not isinstance(crop, str):
            raise HTTPException(422, 'Проверьте фотографию и область выделения')
        data = await photo.read(MAX_UPLOAD_BYTES + 1)
        if len(data) > MAX_UPLOAD_BYTES:
            raise HTTPException(413, 'Максимальный размер фото — 8 МБ')
        if not data:
            raise HTTPException(422, 'Файл пустой')
        return data, crop
    finally:
        await form.close()
