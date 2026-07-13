from aios_daemon.config import Config


def test_defaults():
    cfg = Config()
    assert cfg.model == "qwen2.5:7b"
    assert cfg.port == 8800
    assert cfg.ollama_url.startswith("http://")


def test_env_overrides(monkeypatch):
    monkeypatch.setenv("AIOS_MODEL", "qwen2.5:14b")
    monkeypatch.setenv("AIOS_PORT", "9000")
    cfg = Config()
    assert cfg.model == "qwen2.5:14b"
    assert cfg.port == 9000
