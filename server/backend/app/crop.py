"""Server-side normalized crop, shared by browser and Flutter clients."""
from io import BytesIO
from PIL import Image, ImageOps, UnidentifiedImageError
from .image_features import InvalidImage


def crop_image(data: bytes, selection: str | None) -> bytes:
    if not selection:
        return data
    try:
        vals = [float(v) for v in selection.split(',')]
        if len(vals) != 4:
            raise ValueError()
        x, y, w, h = vals
        if not all(0 <= v <= 1 for v in vals) or w < 0.05 or h < 0.05 or x + w > 1.00001 or y + h > 1.00001:
            raise ValueError()
    except (TypeError, ValueError):
        raise InvalidImage('Неверная область выделения (x,y,width,height от 0 до 1)')
    try:
        with Image.open(BytesIO(data)) as im:
            if im.format not in ('JPEG', 'PNG', 'WEBP'):
                raise InvalidImage('Поддерживаются JPEG, PNG и WebP')
            im = ImageOps.exif_transpose(im).convert('RGB')
            W, H = im.size
            bounds = (round(x * W), round(y * H), round((x + w) * W), round((y + h) * H))
            if bounds[2] - bounds[0] < 24 or bounds[3] - bounds[1] < 24:
                raise InvalidImage('Выделенная область слишком маленькая')
            cropped = im.crop(bounds)
            out = BytesIO()
            cropped.save(out, 'JPEG', quality=92, optimize=True)
            return out.getvalue()
    except (OSError, UnidentifiedImageError, Image.DecompressionBombError) as exc:
        raise InvalidImage('Не удалось обработать изображение') from exc
