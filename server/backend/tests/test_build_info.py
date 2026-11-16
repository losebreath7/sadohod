from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.admin_auth import require_admin
from backend.app.build_info import BUILD_INFO


def test_version_is_consistent_across_api_surfaces():
    client = TestClient(app)
    app.dependency_overrides[require_admin] = lambda: None
    try:
        for path in ('/health', '/api/v1/admin/status'):
            response = client.get(path)
            assert response.status_code == 200
            assert {k: response.json()[k] for k in BUILD_INFO} == BUILD_INFO
        assert client.get('/openapi.json').json()['info']['version'] == BUILD_INFO['full_version']
        assert client.get('/health').json()['server_patch'] == BUILD_INFO['build_number']
        for path in ('admin.html', 'merchant_admin.html'):
            response = client.get('/preview/' + path)
            assert 'data-build-label' in response.text
            assert 'build_info.js' in response.text
            assert 'no-store' in response.headers['cache-control']
    finally:
        app.dependency_overrides.pop(require_admin, None)
