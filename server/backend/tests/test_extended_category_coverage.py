"""Coverage and semantic safety for extended product recognition.

These tests verify category mapping, aliases and HTTP search integration using
mocked photo votes. They do not measure real OpenCLIP photo accuracy.
"""
import pytest

from backend.app.catalog_taxonomy import BY_ID, NODES_V1, resolve_leaf
from backend.app.category_inference import (
    PROMPTS, VISUAL_LEAF_PROMPTS, ANIMAL_TOY_PROMPTS,
    ROOT_TO_LEGACY, legacy_for_leaf,
)
from backend.app.product_semantics import (
    LEAF_FACETS, TOY_SPECIES, category_facets, query_terms,
    title_facets,
)
from backend.app.text_search import visual_prompt
from test_product_semantic_facets import _published_unnamed, _reclassify


def test_visual_prompts_cover_all_safe_product_leaves():
    parents = {parent for _, parent, _ in NODES_V1 if parent}
    leaves = set(BY_ID) - parents
    # Gender and age cannot be determined reliably from a single image.
    intentional_title_only = {
        'clothing-men', 'clothing-kids-jackets',
        'shoes-women-sneakers', 'shoes-men-sneakers',
        'shoes-kids-sneakers',
    }
    assert leaves - set(VISUAL_LEAF_PROMPTS) == intentional_title_only
    assert len(VISUAL_LEAF_PROMPTS) - 1 == 59
    assert len(LEAF_FACETS) >= 59
    for leaf, prompts in VISUAL_LEAF_PROMPTS.items():
        if leaf == '_other':
            continue
        assert leaf in BY_ID, leaf
        assert leaf in LEAF_FACETS, leaf
        assert prompts and all(prompt.startswith(('a ', 'an ', 'the '))
                               for prompt in prompts)
        assert legacy_for_leaf(leaf) in PROMPTS
        assert category_facets(leaf)


@pytest.mark.parametrize('title,leaf', [
    ('Настольная игра с карточками', 'toys-board'),
    ('Нижнее белье', 'clothing-underwear'),
    ('Шапка зимняя', 'bags-hats'),
    ('Ремень кожаный', 'bags-belts'),
    ('Женские духи', 'beauty-fragrance'),
    ('Кружка керамическая', 'home-cups'),
    ('Статуэтка для дома', 'home-decor'),
    ('Органайзер для хранения', 'home-storage'),
    ('Ковер', 'home-textile'),
    ('Зарядная лампа', 'electronics-lighting'),
    ('Чехол для смартфона', 'electronics-phone'),
    ('Поильник детский', 'kids-feeding'),
    ('Гантели', 'sport-fitness'),
    ('Туристическая палатка', 'sport-camping'),
    ('Ошейник для собаки', 'pets-collars'),
    ('Лежанка для кошки', 'pets-beds'),
    ('Молоток', 'tools-hand'),
    ('Шуруповерт', 'tools-electric'),
    ('Новогодняя гирлянда', 'seasonal-christmas'),
    ('Подарочный набор', 'seasonal-gifts'),
    ('Серебряный браслет', 'jewelry-bracelets'),
    ('Золотое колье', 'jewelry-necklaces'),
])
def test_explicit_product_title_uses_existing_leaf(title, leaf):
    assert resolve_leaf(title) == leaf


@pytest.mark.parametrize('title', [
    'Ремень для часов',
    'Чехол для куклы',
    'Рисунок дракона на ткани',
    'Сумка с принтом кукла',
    'Куртка и брюки',
])
def test_accessory_and_multi_product_titles_do_not_invent_category(title):
    assert resolve_leaf(title) is None


def test_specific_phone_case_is_the_actual_product():
    assert resolve_leaf('Чехол для телефона iPhone') == 'electronics-phone'
    assert resolve_leaf('Чехол для смартфона с принтом обезьяны') is None


@pytest.mark.parametrize('word,canonical', [
    ('настолка', 'настольная игра'),
    ('памперс', 'подгузники'),
    ('рюкзаки', 'рюкзак'),
    ('кошельки', 'кошелек'),
    ('зарядник', 'зарядка'),
    ('львенок', 'лев'),
    ('лисенок', 'лиса'),
    ('слоник', 'слон'),
    ('единорожка', 'единорог'),
    ('динозавры', 'динозавр'),
])
def test_synonyms_are_indexed_as_canonical_search_words(word, canonical):
    assert canonical in query_terms(word)


@pytest.mark.parametrize('word,expected', [
    ('кошелек', 'wallet'), ('ошейник', 'collar'),
    ('кружка', 'mug'), ('подарочный набор', 'gift'),
    ('настолка', 'board game'), ('зарядник', 'charger'),
    ('слоник', 'elephant'), ('лисенок', 'fox'),
])
def test_visual_search_has_a_grounded_prompt_for_new_terms(word, expected):
    assert expected in visual_prompt(word)


def test_fifteen_plush_species_supported_without_applying_to_clothing():
    species = set(ANIMAL_TOY_PROMPTS) - {'_other'}
    assert species == set(TOY_SPECIES)
    assert len(species) == 15
    assert title_facets('Мягкая игрушка панда', 'toys-plush') == {'панда': 'title'}
    assert title_facets('Футболка с пандой', 'clothing-tshirts') == {}
    assert title_facets('Чехол с пандой', 'toys-plush') == {}


@pytest.mark.parametrize('broad,leaf,word', [
    ('Сумки', 'bags-wallets', 'кошелек'),
    ('Красота и уход', 'beauty-fragrance', 'парфюм'),
    ('Товары для дома', 'home-cups', 'кружка'),
    ('Игрушки', 'toys-board', 'настольная игра'),
    ('Детские товары', 'kids-diapers', 'подгузники'),
    ('Зоотовары', 'pets-collars', 'ошейник'),
    ('Канцтовары', 'office-notebooks', 'блокнот'),
    ('Инструменты и ремонт', 'tools-electric', 'дрель'),
    ('Сезонные товары', 'seasonal-christmas', 'новогодняя игрушка'),
])
def test_nameless_published_product_searchable_by_new_image_type(
    env, monkeypatch, broad, leaf, word
):
    client, db_factory, product_id = _published_unnamed(env)
    _reclassify(db_factory, monkeypatch, broad, leaf)
    product = client.get(f'/api/v1/products/{product_id}').json()
    assert product['category_id'] == leaf
    assert word in product['search_tags']
    for url in ('/api/v1/search/text', '/api/v1/products'):
        result = client.get(url, params={'q': word})
        assert result.status_code == 200, result.text
        assert product_id in {p['id'] for p in result.json()['items']}
