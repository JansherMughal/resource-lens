"""Placeholder OpenSearch resolver — replace with opensearch-py requests in production."""

import json
import os


def handler(event, context):
    endpoint = os.environ.get("OPENSEARCH_ENDPOINT", "")
    return {
        "data": json.dumps(
            {
                "message": "Search placeholder",
                "opensearchEndpoint": endpoint,
                "received": event,
            }
        )
    }
