"""Placeholder Cost Lambda — runs a trivial Athena query or returns config (extend for real CUR analytics)."""

import json
import os


def handler(event, context):
    return {
        "workgroup": os.environ.get("ATHENA_WORKGROUP", ""),
        "database": os.environ.get("ATHENA_DATABASE", ""),
        "curBucket": os.environ.get("CUR_BUCKET", ""),
        "resultsBucket": os.environ.get("RESULTS_BUCKET", ""),
        "event": event,
    }
