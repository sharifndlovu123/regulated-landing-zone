from app import app

client = app.test_client()


def test_health():
    assert client.get("/health").get_json() == {"status": "ok"}


def test_home_reports_env(monkeypatch):
    monkeypatch.setenv("APP_ENV", "prod")
    assert client.get("/").get_json()["env"] == "prod"
