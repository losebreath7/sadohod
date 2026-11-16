"""Conservative title rules; no model downloads or image recognition implied.

Only missing categories are filled. Existing/manual categories survive edits.
Unknown titles and mixed-category sets are left for moderation.
"""
import re

UNASSIGNED = 'Без категории'
WORDS = {
    'Верхняя одежда': 'куртка куртки куртку пальто пуховик пуховики ветровка ветровки плащ плащи шуба шубы дубленка дубленки',
    'Сумки': 'сумка сумки сумку рюкзак рюкзаки клатч клатчи',
    'Обувь': 'кроссовки кроссовок кеды кед ботинки ботинок сапоги сапог туфли туфель босоножки сандалии мокасины лоферы',
    'Платья': 'платье платья платьев сарафан сарафаны',
    'Одежда': 'футболка футболки футболку худи свитшот свитшоты свитер свитеры джинсы брюки рубашка рубашки юбка юбки шорты блузка блузки кардиган кардиганы',
}
TOKENS = {category: set(words.split()) for category, words in WORDS.items()}
# These titles often describe accessories or a motif, not the named product.
AMBIGUOUS = set('для чехол чехлы ремень ремни брелок брелоки рисунок рисунком принт принтом изображение изображением выкройка выкройки ткань кукла куклы'.split())


def is_unassigned(value: str) -> bool:
    return not value.strip() or value.strip().casefold() == UNASSIGNED.casefold()


def resolve_category(title: str, supplied: str = '') -> str:
    if not is_unassigned(supplied):
        return supplied.strip()
    words = set(re.findall(r'[а-яa-z]+', title.casefold().replace('ё', 'е')))
    if words & AMBIGUOUS:
        return UNASSIGNED
    matches = [category for category, tokens in TOKENS.items() if words & tokens]
    return matches[0] if len(matches) == 1 else UNASSIGNED
