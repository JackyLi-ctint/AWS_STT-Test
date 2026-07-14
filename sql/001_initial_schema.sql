CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_name VARCHAR(255) NOT NULL,
    s3_bucket VARCHAR(255) NOT NULL,
    s3_key TEXT NOT NULL,
    transcribe_job_name VARCHAR(200) NOT NULL UNIQUE,
    language VARCHAR(10) NOT NULL,
    transcript_text TEXT NOT NULL,
    source_etag VARCHAR(128),
    transcript_uri TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT transcripts_language_chk CHECK (language IN ('en-US', 'zh-CN', 'zh-HK')),
    CONSTRAINT transcripts_source_uniq UNIQUE (s3_bucket, s3_key, COALESCE(source_etag, ''))
);

CREATE TABLE transcript_segments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transcript_id UUID NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
    segment_index INTEGER NOT NULL,
    start_time NUMERIC(10, 3),
    end_time NUMERIC(10, 3),
    text TEXT NOT NULL,
    confidence NUMERIC(5, 4),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT transcript_segments_idx_uniq UNIQUE (transcript_id, segment_index)
);

CREATE INDEX idx_transcripts_language ON transcripts(language);
CREATE INDEX idx_transcripts_file_name ON transcripts(file_name);
CREATE INDEX idx_segments_transcript_id ON transcript_segments(transcript_id);
CREATE INDEX idx_segments_time_range ON transcript_segments(transcript_id, start_time, end_time);