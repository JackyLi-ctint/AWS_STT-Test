import hashlib
import json
import re
from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Optional, Tuple


SUPPORTED_LANGUAGES = {"en-US", "zh-CN", "zh-HK"}
WORD_TYPES = {"pronunciation", "punctuation"}


class TranscriptProcessingError(ValueError):
    pass


@dataclass(frozen=True)
class TranscriptMetadata:
    job_name: str
    transcript_uri: str
    media_uri: str
    language_code: str
    s3_bucket: str
    s3_key: str
    source_etag: Optional[str]


def extract_language_from_key(object_key: str) -> str:
    cleaned_key = object_key.lstrip("/")
    if not cleaned_key:
        raise TranscriptProcessingError("S3 object key is empty.")

    language = cleaned_key.split("/", 1)[0]
    if language not in SUPPORTED_LANGUAGES:
        raise TranscriptProcessingError(
            f"Unsupported language prefix '{language}' in S3 key '{object_key}'."
        )

    return language


def build_transcribe_job_name(bucket: str, object_key: str, object_etag: Optional[str]) -> str:
    suffix_source = f"{bucket}:{object_key}:{object_etag or ''}"
    digest = hashlib.sha256(suffix_source.encode("utf-8")).hexdigest()[:16]
    normalized_name = re.sub(r"[^A-Za-z0-9._-]", "-", object_key.rsplit("/", 1)[-1])
    normalized_name = normalized_name[:80].strip("-") or "audio"
    return f"{normalized_name}-{digest}"


def build_output_key_prefix(language_code: str, job_name: str, base_prefix: str = "jobs/") -> str:
    prefix = base_prefix.strip("/")
    if prefix:
        prefix = f"{prefix}/"
    return f"{prefix}{language_code}/{job_name}/"


def parse_s3_uri(uri: str) -> Tuple[str, str]:
    if not uri.startswith("s3://"):
        raise TranscriptProcessingError(f"Unsupported S3 URI '{uri}'.")

    without_scheme = uri[5:]
    bucket, separator, key = without_scheme.partition("/")
    if not bucket or not separator or not key:
        raise TranscriptProcessingError(f"Invalid S3 URI '{uri}'.")

    return bucket, key


def normalize_decimal(value: Any) -> Optional[Decimal]:
    if value in (None, ""):
        return None
    return Decimal(str(value))


def _coalesce_segment_text(items: Iterable[Dict[str, Any]]) -> str:
    buffer: List[str] = []
    for item in items:
        alternatives = item.get("alternatives") or []
        if not alternatives:
            continue

        token = alternatives[0].get("content", "")
        if not token:
            continue

        if item.get("type") == "punctuation" and buffer:
            buffer[-1] = f"{buffer[-1]}{token}"
            continue

        buffer.append(token)

    return " ".join(buffer).strip()


def build_segment_rows(transcript_id: str, transcript_payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    items = transcript_payload.get("results", {}).get("items", [])
    rows: List[Dict[str, Any]] = []
    current_tokens: List[Dict[str, Any]] = []
    segment_index = 0

    for item in items:
        item_type = item.get("type")
        if item_type not in WORD_TYPES:
            continue

        current_tokens.append(item)

        if item_type == "punctuation":
            rows.append(_finalize_segment(transcript_id, current_tokens, segment_index))
            segment_index += 1
            current_tokens = []

    if current_tokens:
        rows.append(_finalize_segment(transcript_id, current_tokens, segment_index))

    return [row for row in rows if row["text"]]


def _finalize_segment(
    transcript_id: str, tokens: List[Dict[str, Any]], segment_index: int
) -> Dict[str, Any]:
    text = _coalesce_segment_text(tokens)
    first_word = next((token for token in tokens if token.get("type") == "pronunciation"), None)
    last_word = next(
        (token for token in reversed(tokens) if token.get("type") == "pronunciation"), None
    )
    confidences = []
    for token in tokens:
        alternatives = token.get("alternatives") or []
        if not alternatives:
            continue
        confidence = alternatives[0].get("confidence")
        if confidence not in (None, ""):
            confidences.append(Decimal(str(confidence)))

    segment_key = f"{transcript_id}:{segment_index}:{text}".encode("utf-8")
    segment_id = hashlib.sha256(segment_key).hexdigest()[:32]

    return {
        "id": segment_id,
        "transcript_id": transcript_id,
        "segment_index": segment_index,
        "start_time": normalize_decimal(first_word.get("start_time") if first_word else None),
        "end_time": normalize_decimal(last_word.get("end_time") if last_word else None),
        "text": text,
        "confidence": _average(confidences),
    }


def _average(values: List[Decimal]) -> Optional[Decimal]:
    if not values:
        return None
    return sum(values) / Decimal(len(values))


def normalize_transcribe_event(event: Dict[str, Any]) -> TranscriptMetadata:
    detail = event.get("detail") or {}
    status = detail.get("TranscriptionJobStatus")
    if status != "COMPLETED":
        raise TranscriptProcessingError(
            f"Transcribe job status must be COMPLETED, received '{status}'."
        )

    transcript = detail.get("Transcript") or {}
    media = detail.get("Media") or {}
    language_code = detail.get("LanguageCode")
    job_name = detail.get("TranscriptionJobName")
    transcript_uri = transcript.get("TranscriptFileUri")
    media_uri = media.get("MediaFileUri")

    if not all([language_code, job_name, transcript_uri, media_uri]):
        raise TranscriptProcessingError("Transcribe completion event is missing required fields.")

    bucket, key = parse_s3_uri(media_uri)

    return TranscriptMetadata(
        job_name=job_name,
        transcript_uri=transcript_uri,
        media_uri=media_uri,
        language_code=language_code,
        s3_bucket=bucket,
        s3_key=key,
        source_etag=detail.get("SourceEtag"),
    )


def build_transcript_row(metadata: TranscriptMetadata, transcript_payload: Dict[str, Any]) -> Dict[str, Any]:
    transcript_texts = transcript_payload.get("results", {}).get("transcripts", [])
    transcript_text = transcript_texts[0].get("transcript", "") if transcript_texts else ""
    transcript_id = hashlib.sha256(
        f"{metadata.s3_bucket}:{metadata.s3_key}:{metadata.job_name}".encode("utf-8")
    ).hexdigest()[:32]

    return {
        "id": transcript_id,
        "file_name": metadata.s3_key.rsplit("/", 1)[-1],
        "s3_bucket": metadata.s3_bucket,
        "s3_key": metadata.s3_key,
        "transcribe_job_name": metadata.job_name,
        "language": metadata.language_code,
        "transcript_text": transcript_text,
        "source_etag": metadata.source_etag,
        "transcript_uri": metadata.transcript_uri,
    }


def load_transcript_payload(raw_payload: str) -> Dict[str, Any]:
    try:
        return json.loads(raw_payload)
    except json.JSONDecodeError as exc:
        raise TranscriptProcessingError("Unable to parse transcript JSON payload.") from exc