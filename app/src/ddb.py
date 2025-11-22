import os, boto3
from botocore.exceptions import ClientError, BotoCoreError

_table = None

def _get_table():
    """Get or create the DynamoDB table resource (lazy initialization)"""
    global _table
    if _table is None:
        region = os.environ.get("AWS_REGION", "eu-west-2")
        if not region:
            raise ValueError("AWS_REGION environment variable must be set")
        table_name = os.environ.get("TABLE_NAME")
        if not table_name:
            raise ValueError("TABLE_NAME environment variable must be set")
        _table = boto3.resource("dynamodb", region_name=region).Table(table_name)
    return _table

def put_mapping(short_id: str, url: str):
    """Store URL mapping in DynamoDB with error handling"""
    try:
        _get_table().put_item(Item={"id": short_id, "url": url})
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        if error_code == "ResourceNotFoundException":
            raise RuntimeError(f"DynamoDB table not found. Check TABLE_NAME environment variable.") from e
        elif error_code in ["ProvisionedThroughputExceededException", "ThrottlingException"]:
            raise RuntimeError("DynamoDB is throttling requests. Please try again later.") from e
        else:
            raise RuntimeError(f"Failed to store URL mapping: {error_code}") from e
    except BotoCoreError as e:
        raise RuntimeError(f"AWS service error: {str(e)}") from e
    except Exception as e:
        raise RuntimeError(f"Unexpected error storing URL mapping: {str(e)}") from e

def get_mapping(short_id: str):
    """Retrieve URL mapping from DynamoDB with error handling"""
    try:
        resp = _get_table().get_item(Key={"id": short_id})
        return resp.get("Item")
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        if error_code == "ResourceNotFoundException":
            raise RuntimeError(f"DynamoDB table not found. Check TABLE_NAME environment variable.") from e
        elif error_code in ["ProvisionedThroughputExceededException", "ThrottlingException"]:
            raise RuntimeError("DynamoDB is throttling requests. Please try again later.") from e
        else:
            raise RuntimeError(f"Failed to retrieve URL mapping: {error_code}") from e
    except BotoCoreError as e:
        raise RuntimeError(f"AWS service error: {str(e)}") from e
    except Exception as e:
        raise RuntimeError(f"Unexpected error retrieving URL mapping: {str(e)}") from e
