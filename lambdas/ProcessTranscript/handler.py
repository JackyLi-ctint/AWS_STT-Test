import json
import os
from typing import Any, Dict
from urllib.request import urlopen

from lambdas.shared.transcript_processing import (
    build_segment_rows,
    build_transcript_row,
    load_transcript_payload,
    normalize_transcribe_event,
)


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    metadata = normalize_transcribe_event(event)
    transcript_payload = _download_transcript_payload(metadata.transcript_uri)
    transcript_row = build_transcript_row(metadata, transcript_payload)
    segment_rows = build_segment_rows(transcript_row["id"], transcript_payload)

    persistence_target = os.environ.get("TRANSCRIPT_OUTPUT_TABLE", "not-configured")
    result = {
        "persistence_target": persistence_target,
        "transcript": transcript_row,
        "segments": segment_rows,
    }

    print(json.dumps(result, default=str))
    return {
        "transcript_id": transcript_row["id"],
        "segment_count": len(segment_rows),
        "language": transcript_row["language"],
    }


def _download_transcript_payload(transcript_uri: str) -> Dict[str, Any]:
    with urlopen(transcript_uri) as response:
        body = response.read().decode("utf-8")
    return load_transcript_payload(body)