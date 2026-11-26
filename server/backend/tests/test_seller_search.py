from backend.app.models import Seller, Pavilion
from backend.app.merchant_models import PavilionClaim
from test_merchant_v080 import env


def test_public_seller_search_matches_unicode_names_and_approved_addresses(env):
    client, _, factory, _ = env
    with factory() as db:
        db.add_all([Pavilion(id='search-primary', code='А-777', zone='Корпус А'),
                    Pavilion(id='search-extra', code='Б-888', zone='Корпус Б')])
        db.flush()
        db.add(Seller(id='search-seller', name='Лосёбрит Магазин', pavilion_id='search-primary'))
        db.flush()
        db.add(PavilionClaim(seller_id='search-seller', pavilion_id='search-extra',
                             zone_key='корпус б', code_key='б-888'))
        db.commit()
    for query in ('ЛОСЕБРИТ', 'магазин', 'а-777', 'б-888'):
        response = client.get('/api/v1/search/text', params={'q':query})
        assert response.status_code == 200, response.text
        body = response.json()
        assert 'items' in body
        found = [s for s in body['sellers'] if s['id'] == 'search-seller']
        assert len(found) == 1
        assert set(found[0]['pavilions']) == {'А-777', 'Б-888'}
    assert client.get('/api/v1/search/text', params={'q':'нет такого магазина 987654'}).json()['sellers'] == []
