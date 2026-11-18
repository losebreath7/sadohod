"""Seller upload endpoints enforce six photos across separate requests."""
from test_instant_publication import setup_seller
from test_merchant_v080 import env, photo


def test_seller_photo_cap_and_replacement(env):
    client, auth, _pavilion = setup_seller(env)
    created = client.post('/api/v1/merchant/products', headers=auth,
                          json={'title': 'Фото товара'})
    assert created.status_code == 201, created.text
    pid = created.json()['id']
    endpoint = f'/api/v1/merchant/products/{pid}/images'

    for index in range(6):
        uploaded = client.post(endpoint, headers=auth,
            files={'files': (f'image{index}.jpg', photo(), 'image/jpeg')})
        assert uploaded.status_code == 201, uploaded.text

    assert len(client.get(f'/api/v1/merchant/products/{pid}',
                          headers=auth).json()['image_items']) == 6
    extra = client.post(endpoint, headers=auth,
        files={'files': ('extra.jpg', photo(), 'image/jpeg')})
    assert extra.status_code == 422, extra.text
    assert '6' in extra.json()['detail']

    images = client.get(f'/api/v1/merchant/products/{pid}',
                        headers=auth).json()['image_items']
    replaced = client.post(endpoint, headers=auth,
        data={'replace_id': images[0]['id']},
        files={'files': ('replacement.jpg', photo(), 'image/jpeg')})
    assert replaced.status_code == 201, replaced.text
    final_images = client.get(f'/api/v1/merchant/products/{pid}',
                              headers=auth).json()['image_items']
    assert len(final_images) == 6
