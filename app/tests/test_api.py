from fastapi.testclient import TestClient
from unittest.mock import patch
from src.main import app

client = TestClient(app)

def test_health():
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"

@patch('src.ddb.put_mapping')
@patch('src.ddb.get_mapping')
def test_shorten(mock_get, mock_put):
    r = client.post("/shorten", json={"url": "https://example.com"})
    assert r.status_code == 200
    assert "short" in r.json()
    assert r.json()["url"] == "https://example.com"
    mock_put.assert_called_once()

@patch('src.ddb.get_mapping')
def test_resolve_not_found(mock_get):
    mock_get.return_value = None
    r = client.get("/nonexistent")
    assert r.status_code == 404

@patch('src.ddb.get_mapping')
def test_resolve_found(mock_get):
    mock_get.return_value = {"id": "abc12345", "url": "https://example.com"}
    r = client.get("/abc12345", follow_redirects=False)
    assert r.status_code == 307  # Temporary redirect
