"""Production FastAPI config rejects unsafe runtime even if preflight is bypassed."""
import os
import subprocess
import sys

ENV = {
    "SADOHOD_ENV": "production",
    "DEMO_SEED": "0",
    "DATABASE_URL": "postgresql+psycopg://sadohod:" + "A" * 64 + "@db:5432/sadohod",
    "SEARCH_BACKEND": "clip",
    "ALLOWED_ORIGINS": "https://sadohod.ru",
    "SMTP_HOST": "smtp.mail.ru",
    "SMTP_PORT": "465",
    "SMTP_FROM": "no-reply@sadohod.ru",
    "SMTP_USER": "no-reply@sadohod.ru",
    "SMTP_PASSWORD": "B" * 20,
    "ADMIN_TOKEN": "C" * 48,
}


def probe(**changes):
    environment = {**os.environ, **ENV, **changes}
    return subprocess.run([sys.executable, "-c",
                           "from backend.app.config import DEMO_SEED, ALLOWED_ORIGINS; "
                           "print(DEMO_SEED, ALLOWED_ORIGINS)"],
                          env=environment, capture_output=True, text=True, timeout=15)


def test_production_runtime_valid():
    result = probe()
    assert result.returncode == 0, result.stderr
    assert "False" in result.stdout
    assert "https://sadohod.ru" in result.stdout


def test_production_runtime_rejects_demo():
    result = probe(DEMO_SEED="1")
    assert result.returncode != 0
    assert "DEMO_SEED" in result.stderr


def test_production_runtime_requires_real_database():
    assert probe(DATABASE_URL="sqlite:////tmp/test.db").returncode != 0


def test_production_runtime_requires_clip_and_smtp():
    assert probe(SEARCH_BACKEND="classic").returncode != 0
    assert probe(SMTP_HOST="smtp.example.com").returncode != 0
    assert probe(SMTP_PASSWORD="").returncode != 0


def test_production_runtime_forbids_local_cors():
    assert probe(ALLOWED_ORIGINS="http://localhost:3000").returncode != 0
    assert probe(ALLOWED_ORIGINS="https://api.example.com").returncode != 0
    assert probe(ALLOWED_ORIGINS="http://sadohod.ru").returncode != 0
    assert probe(ALLOWED_ORIGINS="").returncode == 0
