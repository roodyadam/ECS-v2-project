from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock
import pytest

# Patch _get_table before importing app to prevent boto3 initialization
@pytest.fixture(autouse=True, scope="function")
def mock_dynamodb():
    """Automatically mock DynamoDB for all tests"""
    with patch('src.ddb._get_table') as mock_get_table:
        mock_table = MagicMock()
        mock_get_table.return_value = mock_table
        yield mock_table

# Import app inside each test to ensure mocks are active
@pytest.fixture
def app_client():
    """Create a test client with mocked DynamoDB"""
    from src.main import app
    return TestClient(app)

def test_health(app_client):
    r = app_client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"

def test_shorten(app_client, mock_dynamodb):
    r = app_client.post("/shorten", json={"url": "https://example.com"})
    assert r.status_code == 200
    assert "short" in r.json()
    assert r.json()["url"] == "https://example.com"
    # Verify put_item was called
    mock_dynamodb.put_item.assert_called_once()

def test_resolve_not_found(app_client, mock_dynamodb):
    # Mock get_item to return empty response (no Item key)
    mock_dynamodb.get_item.return_value = {}
    r = app_client.get("/nonexistent")
    assert r.status_code == 404

def test_resolve_found(app_client, mock_dynamodb):
    # Mock get_item to return an item
    mock_dynamodb.get_item.return_value = {"Item": {"id": "abc12345", "url": "https://example.com"}}
    r = app_client.get("/abc12345", follow_redirects=False)
    assert r.status_code == 307  # Temporary redirect
