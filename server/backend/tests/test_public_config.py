"""Public deployment cannot silently inherit local demo configuration."""
import os
import subprocess
import sys


def _config_probe(**overrides):
    env = {**os.environ, **overrides}
    return subprocess.run(
        [sys.executable, "-c",
         "from backend.app.config import SADOHOD_ENV, DEMO_SEED, ALLOWED_ORIGINS; "
         "print(SADOHOD_ENV, DEMO_SEED, ALLOWED_ORIGINS)"],
        env=env, capture_output=True, text=True, timeout=15)


def test_staging_rejects_demo_seed():
    result = _config_probe(SADOHOD_ENV="staging", DEMO_SEED="1")
    assert result.returncode != 0
    assert "отключить DEMO_SEED" in result.stderr


def test_production_rejects_demo_seed():
    result = _config_probe(SADOHOD_ENV="production", DEMO_SEED="1")
    assert result.returncode != 0
    assert "отключить DEMO_SEED" in result.stderr


def test_staging_has_explicit_web_cors_origins():
    result = _config_probe(
        SADOHOD_ENV="staging", DEMO_SEED="0",
        ALLOWED_ORIGINS="https://buyer.example.com, https://seller.example.com")
    assert result.returncode == 0, result.stderr
    assert "staging False" in result.stdout
    assert "https://buyer.example.com" in result.stdout
    assert "https://seller.example.com" in result.stdout


def test_invalid_deployment_mode_fails_fast():
    result = _config_probe(SADOHOD_ENV="publik", DEMO_SEED="0")
    assert result.returncode != 0
    assert "SADOHOD_ENV" in result.stderr
