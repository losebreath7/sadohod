"""Contextual triage of seller listings (not a legal classifier).

Only a moderator rejects an item. Uncertain text/image matches enter the
existing pending queue before any public offer is created. Cosine similarity
is NOT a calibrated probability, and the visual thresholds need field data.
"""
import math
import re
from functools import lru_cache

from .config import SEARCH_BACKEND
from .models import ImageMLEmbedding
from .ml_clip import MODEL_ID, DIM


def words(pattern):
    return re.compile(r'\b(?:' + pattern + r')\b', re.I)


# Explicit item claims; do not match loosely related words ("патрон" in a
# lightbulb listing or "гранат" as a fruit/jewel).
RISK_TEXT = (
    ('оружие', words(
        r'пистолет\w*|револьвер\w*|винтовк\w*|огнестрел\w*|'
        r'боев\w*\s+нож\w*|боев\w*\s+патрон\w*|боеприпас\w*|'
        r'огнестрельн\w*\s+оруж\w*|автомат\s+калашников\w*|'
        r'ручн\w*\s+гранат\w*|кастет\w*|электрошокер\w*|'
        r'арбалет\w*|firearm|handgun|pistol|rifle|live\s+ammunition')),
    ('запрещённые вещества', words(
        r'наркотик\w*|героин\w*|кокаин\w*|метамфетамин\w*|'
        r'амфетамин\w*|экстази|мефедрон\w*|псилоцибин\w*|'
        r'марихуан\w*|гашиш\w*|cocaine|heroin|methamphetamine')),
    ('взрывчатка и опасные химикаты', words(
        r'взрывчат\w*|взрывн\w*\s+устройств\w*|самодельн\w*\s+бомб\w*|'
        r'взрывпакет\w*|боев\w*\s+гранат\w*|'
        r'токсичн\w*\s+яд\w*|ядовит\w*\s+веществ\w*|explosive\s+device')),
    ('порнографический контент', words(
        r'порнографи\w*|порно(?:графическ\w*)?|'
        r'сексуальн\w*\s+услуг\w*|pornograph\w*|explicit\s+sex')),
    ('эксплуатация несовершеннолетних', words(
        r'детск\w*\s+порнографи\w*|'
        r'сексуальн\w*\s+контент\w*\s+с\s+несовершеннолетн\w*')),
    ('никотин и алкоголь', words(
        r'сигарет\w*|вейп\w*|электронн\w*\s+сигарет\w*|'
        r'никотинов\w*\s+жидкост\w*|табак\w*|'
        r'водк\w*|виски|коньяк\w*|алкогольн\w*\s+напит\w*|'
        r'vape|nicotine\s+liquid')),
    ('рецептурные препараты', words(
        r'рецептурн\w*\s+препарат\w*|лекарств\w*\s+по\s+рецепту|'
        r'антибиотик\w*|анаболическ\w*\s+стероид\w*|'
        r'prescription\s+medication')),
    ('поддельные документы и финансовые инструменты', words(
        r'поддельн\w*\s+(?:паспорт\w*|удостоверени\w*|диплом\w*)|'
        r'фальшив\w*\s+купюр\w*|клон\w*\s+банковск\w*\s+карт\w*|'
        r'fake\s+passport')),
    ('незаконная торговля охраняемыми видами', words(
        r'слонов\w*\s+кост\w*|рог\w*\s+носорог\w*|'
        r'шкур\w*\s+тигр\w*|ivory\s+tusk')),
)
PRINT = words(r'принт\w*|рисунк\w*|изображени\w*|вышивк\w*|наклейк\w*|'
              r'постер\w*|иллюстраци\w*|print|graphic|иллюстрированн\w*')
WEARABLE = words(r'футболк\w*|толстовк\w*|худи|свитшот\w*|'
                 r'кофт\w*|рубашк\w*|одежд\w*|майк\w*|shirt|hoodie')
REPLICA = words(r'игрушечн\w*|водян\w*\s+пистолет\w*|'
                r'брелок\w*|макет\w*|toy|keychain')
REAL_CLAIM = words(r'настоящ\w*|боев\w*|огнестрельн\w*|заряженн\w*|'
                   r'для\s+стрельб\w*|рабоч\w*\s+оруж\w*|real\s+gun')
NUDITY = words(r'обнаж[её]нн\w*|полностью\s+гол\w*|эротическ\w*\s+фото\w*|'
               r'nude\s+photo\w*|explicit\s+nudit\w*')
ART_CONTEXT = words(r'картин\w*|скульптур\w*|рисунк\w*|'
                    r'анатомическ\w*|искусств\w*|painting|artwork')
COUNTERFEIT = words(r'контрафакт\w*|подделк\w*\s+бренд\w*|'
                    r'реплик\w*\s+бренд\w*|fake\s+designer')
VIOLENCE = words(r'сцен\w*\s+казн\w*|реальн\w*\s+расчленени\w*|'
                 r'видео\s+убийств\w*|graphic\s+violence')
EXTREMISM = words(r'символик\w*\s+запрещ[её]нн\w*\s+организаци\w*|'
                 r'пропаганд\w*\s+терроризм\w*')


# English prompts match the OpenCLIP checkpoint; each label has benign
# counterexamples. Treat ambiguity as review, never definite classification.
VISUAL_GROUPS = (
    ('оружие', (
        'a catalog photo of a real handgun being sold',
        'a catalog photo of a real rifle or combat knife',
        'a product photo of live ammunition or a grenade',
    )),
    ('запрещённые вещества', (
        'a product photograph of illicit drugs packed for sale',
        'a product photograph of cannabis buds in bags for sale',
    )),
    ('нагота и сексуальный контент', (
        'a photograph of explicit adult nudity',
        'a sexually explicit adult photograph on a product listing',
    )),
    ('кровавое насилие', (
        'a graphic photograph showing bloody physical violence',
    )),
    ('никотин и алкоголь', (
        'a product photograph of tobacco cigarettes or vape devices',
        'a product photograph of bottles of hard liquor',
    )),
    ('опасные вещества', (
        'a product photograph of a poisonous chemical container for sale',
    )),
)
BENIGN_PROMPTS = (
    'a t-shirt with a printed drawing of a handgun',
    'a fashion hoodie with a printed graphic of a weapon',
    'a colorful plastic toy water gun for children',
    'a decorative keychain shaped like a grenade',
    'a poster with an illustrated pistol',
    'a mannequin wearing a beige skin tone bodysuit',
    'a fashion catalog photograph of a model wearing a swimsuit',
    'a painting showing classical nude figures in a museum',
    'a packet of powdered laundry detergent',
    'a packet of cooking flour or baking ingredients',
    'a bottle of perfume or a cosmetic product',
    'a toy model of a rifle made of plastic',
)


@lru_cache(maxsize=1)
def _prompts():
    from .ml_clip import embed_text
    return ([(label, embed_text(prompt)) for label, prompts in VISUAL_GROUPS
             for prompt in prompts],
            [embed_text(prompt) for prompt in BENIGN_PROMPTS])


def _dot(left, right):
    return sum(float(a) * float(b) for a, b in zip(left, right))


def _text_reason(title, description):
    title = title.casefold()
    description = description.casefold()
    combined = title + ' ' + description
    # A shirt with a printed pistol isn't a gun. But an explicit "real gun"
    # claim must override "shirt" or "print" anywhere else in the description.
    print_context = bool(PRINT.search(title) and WEARABLE.search(title))
    decorative_context = bool(REPLICA.search(title))
    real_claim = bool(REAL_CLAIM.search(combined))
    for label, pattern in RISK_TEXT:
        if pattern.search(title) or pattern.search(description):
            # Only explicit product TITLE context can exempt a graphic/toy.
            # A seller cannot add "shirt with print" in the description
            # of an item titled "pistol" to bypass review.
            if label == 'оружие' and (print_context or decorative_context) and not real_claim:
                continue
            return f'Автопроверка: возможная категория «{label}» (текст)'
    if COUNTERFEIT.search(combined):
        return 'Автопроверка: возможный контрафакт'
    if VIOLENCE.search(combined) or EXTREMISM.search(combined):
        return 'Автопроверка: возможный запрещённый контент'
    if NUDITY.search(combined) and not ART_CONTEXT.search(combined):
        return 'Автопроверка: возможная нагота или откровенный контент'
    return None


def assess(db, product):
    """Return review reason or None. Every photo is examined in clip mode."""
    reason = _text_reason(product.title or '', product.description or '')
    if reason:
        return reason
    if SEARCH_BACKEND != 'clip':
        # Explicit limitation: classic mode only has keyword screening.
        return None
    try:
        risk_prompts, benign_prompts = _prompts()
        for image in product.images:
            stored = db.get(ImageMLEmbedding, (image.id, MODEL_ID))
            if not stored or len(stored.embedding) != DIM:
                return 'Автопроверка: фотография не прошла ML-анализ'
            vector = stored.embedding
            if not all(math.isfinite(float(n)) for n in vector):
                return 'Автопроверка: некорректный ML-вектор'
            risk_scores = [(category, _dot(vector, prompt))
                           for category, prompt in risk_prompts]
            category, risk = max(risk_scores, key=lambda item: item[1])
            benign = max(_dot(vector, prompt) for prompt in benign_prompts)
            # Heuristic similarity thresholds; NOT probabilities, calibrate
            # by category before shipping to a live marketplace.
            if risk >= 0.25 and risk - benign >= 0.025:
                return f'Автопроверка: фотография похожа на «{category}»'
            if risk >= 0.235 and risk - benign >= -0.01:
                return f'Автопроверка: неоднозначное изображение («{category}»)'
    except Exception:
        return 'Автопроверка: ML-анализ временно недоступен'
    return None


def hold_for_review(db, owner, product, reason):
    """Remove published offers and queue review atomically under seller lock."""
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
