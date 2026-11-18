"""Conservative screening before a merchant offer becomes visible.

This is triage, not a legal determination. CLIP cosine similarities are NOT
probabilities. Ambiguous or unavailable ML evidence goes to staff, not public.
"""
import math
import re
from functools import lru_cache

from .config import SEARCH_BACKEND
from .models import ImageMLEmbedding
from .ml_clip import MODEL_ID, DIM

# Text-only rules intentionally focus on explicit physical goods. A weapon
# word on clothing is not evidence that the listing sells a weapon.
WEAPON = re.compile(
    r'\b(?:пистолет\w*|револьвер\w*|винтовк\w*|автомат\w*|ружь\w*|'
    r'огнестрел\w*|боеприпас\w*|патрон\w*|гранат\w*|кастет\w*|'
    r'арбалет\w*|электрошокер\w*|боев\w*\s+нож\w*|'
    r'gun|pistol|rifle|firearm|ammunition|grenade)\b', re.I)
PRINT = re.compile(
    r'\b(?:принт\w*|рисунк\w*|изображени\w*|вышивк\w*|'
    r'наклейк\w*|постер\w*|иллюстраци\w*|print|graphic)\b', re.I)
WEARABLE = re.compile(
    r'\b(?:футболк\w*|толстовк\w*|худи|свитшот\w*|'
    r'кофт\w*|рубашк\w*|одежд\w*|майк\w*|shirt|hoodie)\b', re.I)
OTHER_DANGER = re.compile(
    r'\b(?:взрывчат\w*|взрывн\w*\s+устройств\w*|'
    r'наркотик\w*|ядовит\w*\s+веществ\w*|'
    r'взрывпакет\w*|самодельн\w*\s+бомб\w*)\b', re.I)

# Prompts intentionally represent *objects*, not topical presence of words.
PHYSICAL = (
    'a photograph of a real handgun offered for sale',
    'a photograph of a real rifle firearm offered for sale',
    'a photograph of live ammunition cartridges',
    'a photograph of an actual grenade or explosive device',
    'a photograph of a real combat knife displayed as a product',
)
DECORATIVE = (
    'a photograph of a t-shirt with a printed illustration of a gun',
    'a photograph of a hoodie with a gun graphic printed on fabric',
    'a photograph of a toy water gun made of colorful plastic',
    'a photograph of a harmless decorative keychain shaped like a grenade',
    'a photograph of a poster showing a drawing of a weapon',
)


@lru_cache(maxsize=1)
def _prompts():
    from .ml_clip import embed_text
    return [(embed_text(text), 'physical') for text in PHYSICAL] + [
        (embed_text(text), 'decorative') for text in DECORATIVE]


def _dot(left, right):
    return sum(float(a) * float(b) for a, b in zip(left, right))


def assess(db, product):
    """Return a moderator-readable reason, or None when low-risk.

    In classic-search installations only text can be checked: do not claim
    image AI is active there. In CLIP installations, a missing/broken image
    vector or model is a review condition, never an automatic approval.
    """
    title = product.title or ''
    description = product.description or ''
    combined = (title + ' ' + description).casefold()
    physical_word = bool(WEAPON.search(combined))
    decorative_context = bool(PRINT.search(combined) and WEARABLE.search(combined))
    if OTHER_DANGER.search(combined):
        return 'Автопроверка: возможный опасный или запрещённый товар (текст)'
    if physical_word and not decorative_context:
        return 'Автопроверка: возможный реальный опасный предмет (название/описание)'
    if SEARCH_BACKEND != 'clip':
        return None
    try:
        prompts = _prompts()
        for image in product.images:
            stored = db.get(ImageMLEmbedding, (image.id, MODEL_ID))
            if not stored or len(stored.embedding) != DIM:
                return 'Автопроверка: изображение не прошло ML-анализ'
            vec = stored.embedding
            if not all(math.isfinite(float(n)) for n in vec):
                return 'Автопроверка: некорректный ML-вектор'
            physical = max(_dot(vec, p) for p, kind in prompts if kind == 'physical')
            decorative = max(_dot(vec, p) for p, kind in prompts if kind == 'decorative')
            # Conservative heuristic; must be calibrated using labeled local photos.
            if physical >= 0.24 and physical - decorative >= 0.025:
                return 'Автопроверка: изображение похоже на реальный опасный предмет'
            if physical >= 0.23 and physical - decorative >= -0.015:
                return 'Автопроверка: неоднозначное изображение опасного предмета'
    except Exception:
        return 'Автопроверка: ML-анализ временно недоступен'
    return None


def hold_for_review(db, owner, product, reason):
    """Make every placement nonpublic in the same transaction as status=pending."""
    from sqlalchemy import select
    from .merchant_models import MerchantListing
    from .merchant_operations import drop_offer
    rows = db.scalars(select(MerchantListing).where(
        MerchantListing.product_id == product.id)).all()
    for row in rows:
        if row.offer_id:
            drop_offer(db, row)
        if row.status not in ('deleted', 'paused'):
            row.status = 'pending'
            row.note = reason
    owner.status = 'pending'
    owner.note = reason
    product.details.active = False
