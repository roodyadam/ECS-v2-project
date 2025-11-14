import os, boto3

# Lazy-load the table to avoid boto3 initialization during imports (helps with testing)
_table = None

def _get_table():
    """Get or create the DynamoDB table resource (lazy initialization)"""
    global _table
    if _table is None:
        region = os.environ.get("AWS_REGION", "us-east-1")
        table_name = os.environ.get("TABLE_NAME")
        if not table_name:
            raise ValueError("TABLE_NAME environment variable must be set")
        _table = boto3.resource("dynamodb", region_name=region).Table(table_name)
    return _table

def put_mapping(short_id: str, url: str):
    _get_table().put_item(Item={"id": short_id, "url": url})

def get_mapping(short_id: str):
    resp = _get_table().get_item(Key={"id": short_id})
    return resp.get("Item")
