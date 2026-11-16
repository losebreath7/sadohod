"""Small repeatable smoke benchmark — NOT a real-world quality claim.

Usage in ML Docker:
    docker compose -f docker-compose.yml -f docker-compose.ml.yml exec api python -m backend.tools.evaluate_search
"""
from io import BytesIO
from PIL import Image, ImageEnhance
from sqlalchemy import select
from ..app.config import MEDIA, SEARCH_BACKEND
from ..app.database import SessionLocal
from ..app.models import ProductImage
from ..app.ml_index import nearest_ml_images
from ..app.search import nearest_images


def variant(data, mode):
    with Image.open(BytesIO(data)) as source:
        img = source.convert('RGB')
        if mode == 'brightness':
            img = ImageEnhance.Brightness(img).enhance(.82)
        elif mode == 'resize-jpeg':
            img = img.resize((190, 240))
        elif mode == 'border':
            canvas = Image.new('RGB', (int(img.width*1.2), int(img.height*1.2)), '#ECECEB')
            canvas.paste(img, ((canvas.width-img.width)//2, (canvas.height-img.height)//2))
            img = canvas
        result = BytesIO()
        img.save(result, 'JPEG', quality=75)
        return result.getvalue()


def main():
    total, top1, top3, errors = 0, 0, 0, []
    with SessionLocal() as session:
        imgs = session.scalars(select(ProductImage)).all()
        for img in imgs:
            original = (MEDIA / img.filename).read_bytes()
            for transform in ('brightness','resize-jpeg','border'):
                query = variant(original, transform)
                nearest = (nearest_ml_images if SEARCH_BACKEND == 'clip' else nearest_images)(session, query, limit=12)
                found = [image_id for image_id, _ in nearest]
                total += 1
                top1 += img.id == found[0] if found else 0
                top3 += img.id in found[:3]
                if img.id not in found[:3]:
                    errors.append((img.filename, transform, found[:3]))
    print('DEMO ONLY: same-source transformed images, not independent real photos')
    print(f'engine: {SEARCH_BACKEND} | queries: {total} | hit@1: {top1}/{total} | hit@3: {top3}/{total}')
    for item in errors[:15]:
        print('miss:', *item)


if __name__ == '__main__':
    main()
