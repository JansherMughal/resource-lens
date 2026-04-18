"""Placeholder Gremlin resolver — replace with gremlinpython + Neptune IAM auth in production."""

import json
import os


def handler(event, context):
    endpoint = os.environ.get("NEPTUNE_ENDPOINT", "")
    port = os.environ.get("NEPTUNE_PORT", "8182")
    return {
        "data": json.dumps(
            {
                "message": "Gremlin placeholder",
                "neptuneEndpoint": endpoint,
                "port": port,
                "received": event,
            }
        )
    }
