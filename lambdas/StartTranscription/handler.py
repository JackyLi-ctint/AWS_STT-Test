import os
from typing import Any, Dict, List

import boto3

from lambdas.shared.transcript_processing import (
    build_output_key_prefix,
    build_transcribe_job_name,
    extract_language_from_key,
)


transcribe_client = boto3.client("transcribe")


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    output_bucket = os.environ["TRANSCRIBE_OUTPUT_BUCKET"]
    output_prefix = os.environ.get("TRANSCRIBE_OUTPUT_PREFIX", "jobs/")
    job_name_prefix = os.environ.get("TRANSCRIBE_JOB_NAME_PREFIX", "audio-search")

    started_jobs: List[Dict[str, str]] = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        object_key = record["s3"]["object"]["key"]
        object_etag = record["s3"]["object"].get("eTag") or record["s3"]["object"].get("etag")

        language_code = extract_language_from_key(object_key)
        stable_job_name = build_transcribe_job_name(bucket, object_key, object_etag)
        job_name = f"{job_name_prefix}-{stable_job_name}"[:200]
        media_uri = f"s3://{bucket}/{object_key}"

        transcribe_client.start_transcription_job(
            TranscriptionJobName=job_name,
            LanguageCode=language_code,
            MediaFormat="wav",
            Media={"MediaFileUri": media_uri},
            OutputBucketName=output_bucket,
            OutputKey=build_output_key_prefix(language_code, job_name, output_prefix),
            Tags=[
                {"Key": "source-bucket", "Value": bucket},
                {"Key": "source-key", "Value": object_key[:256]},
                {"Key": "language", "Value": language_code},
            ],
        )

        started_jobs.append(
            {
                "job_name": job_name,
                "media_uri": media_uri,
                "language_code": language_code,
            }
        )

    return {"started_jobs": started_jobs}