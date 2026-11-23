"""Legal publication and public link security tests, without production data."""
import hashlib
import json

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app import legal_documents as legal

from backend.publish_legal import prepare, publish


@pytest.fixture
def documents(tmp_path, monkeypatch):
    monkeypatch.setenv("SADOHOD_LEGAL_DIR", str(tmp_path))
    return tmp_path


def sample():
    return "# Политика конфиденциальности\n\n" + (
        "Настоящий утверждённый текст предназначен для тестирования механизма "
        "публикации. Он не является юридическим документом и не содержит реальных "
        "сведений об операторе или пользователях.\n"
    ) * 6


def test_draft_is_never_public(documents):
    client = TestClient(app)
    for url in ("/legal/privacy", "/api/v1/legal/privacy"):
        r = client.get(url)
        assert r.status_code == 503
        assert "Политика конфиденциальности" not in r.text
    assert client.get("/legal/private-secret").status_code == 404
    assert client.get("/api/v1/legal/private-secret").status_code == 404


def test_published_text_has_same_version_on_web_and_mobile(documents):
    item = prepare(sample(), "privacy", "2026-12-01", "2026-12-01", "QA Reviewer")
    publish(item, documents)
    client = TestClient(app)
    api = client.get("/api/v1/legal/privacy")
    web = client.get("/legal/privacy")
    assert api.status_code == 200
    assert api.json()["version"] == "2026-12-01"
    assert api.json()["sha256"] == hashlib.sha256(sample().encode()).hexdigest()
    assert sample().splitlines()[0].removeprefix("#").strip() in web.text
    assert "Редакция 2026-12-01" in web.text
    assert "max-age=31536000" not in web.headers.get("cache-control", "")


def test_escaping_and_invalid_signature_rejected(documents):
    body = "# <script>alert(1)</script>\n\n" + sample()
    publish(prepare(body, "privacy", "2026-12-01", "2026-12-01", "QA Reviewer"), documents)
    client = TestClient(app)
    result = client.get("/legal/privacy")
    assert result.status_code == 200
    assert "<script>" not in result.text
    assert "&lt;script&gt;" in result.text
    file = documents / "privacy.json"
    data = json.loads(file.read_text())
    data["body"] += "tampered"
    file.write_text(json.dumps(data))
    client = TestClient(app)
    assert client.get("/api/v1/legal/privacy").status_code == 503


def test_version_archive_is_immutable(documents):
    first = prepare(sample(), "privacy", "2026-12-01", "2026-12-01", "QA Reviewer")
    publish(first, documents)
    new_body = sample() + "Новый текст после проверки и даты ввода.\n"
    second = prepare(new_body, "privacy", "2026-12-02", "2026-12-02", "QA Reviewer")
    publish(second, documents)
    with pytest.raises(ValueError):
        publish(prepare(sample() + "Изменённый текст.", "privacy", "2026-12-02",
                        "2026-12-02", "QA Reviewer"), documents)
    publish(second, documents)
    with pytest.raises(ValueError):
        publish(first, documents)
    archived = json.loads((documents / "archive/privacy/2026-12-01.json").read_text())
    assert archived["body"] == sample()
    client = TestClient(app)
    assert client.get("/api/v1/legal/privacy").json()["version"] == "2026-12-02"


def test_publish_blocks_drafts_and_fake_approval(documents):
    for marker in ("[УКАЗАТЬ EMAIL]", "[OPERATOR_NAME]", "[OPERATOR_TAX_ID]", "[OPERATOR_ADDRESS]", "[ДАТА]", "ПРОЕКТ —", "НЕ ПУБЛИКОВАТЬ"):
        with pytest.raises(ValueError):
            prepare(sample() + marker, "privacy", "2026-12-01", "2026-12-01", "QA Reviewer")
    with pytest.raises(ValueError):
        prepare(sample(), "privacy", "2026-12-01", "2026-12-01", "")
    with pytest.raises(ValueError):
        prepare(sample(), "invalid", "2026-12-01", "2026-12-01", "QA Reviewer")
    assert not list(documents.glob("*.json"))


def test_broken_json_symlink_and_missing_approval_fail_closed(documents):
    file = documents / "privacy.json"
    file.write_text('{"slug":"privacy"}')
    client = TestClient(app)
    assert client.get("/api/v1/legal/privacy").status_code == 503
    file.unlink()
    file.symlink_to(documents / "elsewhere")
    client = TestClient(app)
    assert client.get("/api/v1/legal/privacy").status_code == 503
