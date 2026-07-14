import unittest
from decimal import Decimal

from lambdas.shared.transcript_processing import (
    TranscriptProcessingError,
    build_output_key_prefix,
    build_segment_rows,
    build_transcribe_job_name,
    build_transcript_row,
    extract_language_from_key,
    normalize_transcribe_event,
)


class TranscriptProcessingTests(unittest.TestCase):
    def test_extract_language_from_key(self) -> None:
        self.assertEqual(extract_language_from_key("en-US/call001.wav"), "en-US")

    def test_extract_language_rejects_unsupported_prefix(self) -> None:
        with self.assertRaises(TranscriptProcessingError):
            extract_language_from_key("fr-FR/call001.wav")

    def test_build_transcribe_job_name_is_stable(self) -> None:
        first = build_transcribe_job_name("audio-input", "en-US/call001.wav", "abc123")
        second = build_transcribe_job_name("audio-input", "en-US/call001.wav", "abc123")
        self.assertEqual(first, second)

    def test_build_output_key_prefix(self) -> None:
        self.assertEqual(
            build_output_key_prefix("zh-HK", "job-1", "jobs/"),
            "jobs/zh-HK/job-1/",
        )

    def test_normalize_transcribe_event(self) -> None:
        event = {
            "detail": {
                "TranscriptionJobStatus": "COMPLETED",
                "LanguageCode": "en-US",
                "TranscriptionJobName": "job-1",
                "Transcript": {"TranscriptFileUri": "https://example.com/job-1.json"},
                "Media": {"MediaFileUri": "s3://audio-input/en-US/call001.wav"},
                "SourceEtag": "etag-1",
            }
        }

        metadata = normalize_transcribe_event(event)
        self.assertEqual(metadata.s3_bucket, "audio-input")
        self.assertEqual(metadata.s3_key, "en-US/call001.wav")
        self.assertEqual(metadata.source_etag, "etag-1")

    def test_build_transcript_and_segments(self) -> None:
        metadata = normalize_transcribe_event(
            {
                "detail": {
                    "TranscriptionJobStatus": "COMPLETED",
                    "LanguageCode": "en-US",
                    "TranscriptionJobName": "job-1",
                    "Transcript": {"TranscriptFileUri": "https://example.com/job-1.json"},
                    "Media": {"MediaFileUri": "s3://audio-input/en-US/call001.wav"},
                }
            }
        )

        transcript_payload = {
            "results": {
                "transcripts": [{"transcript": "Project Alpha approved."}],
                "items": [
                    {
                        "start_time": "0.0",
                        "end_time": "0.5",
                        "alternatives": [{"content": "Project", "confidence": "0.98"}],
                        "type": "pronunciation",
                    },
                    {
                        "start_time": "0.5",
                        "end_time": "1.0",
                        "alternatives": [{"content": "Alpha", "confidence": "0.97"}],
                        "type": "pronunciation",
                    },
                    {
                        "start_time": "1.0",
                        "end_time": "1.4",
                        "alternatives": [{"content": "approved", "confidence": "0.99"}],
                        "type": "pronunciation",
                    },
                    {
                        "alternatives": [{"content": "."}],
                        "type": "punctuation",
                    },
                ],
            }
        }

        transcript_row = build_transcript_row(metadata, transcript_payload)
        segments = build_segment_rows(transcript_row["id"], transcript_payload)

        self.assertEqual(transcript_row["file_name"], "call001.wav")
        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0]["text"], "Project Alpha approved.")
        self.assertEqual(segments[0]["start_time"], Decimal("0.0"))
        self.assertEqual(segments[0]["end_time"], Decimal("1.4"))
        self.assertEqual(segments[0]["confidence"], Decimal("0.98"))


if __name__ == "__main__":
    unittest.main()