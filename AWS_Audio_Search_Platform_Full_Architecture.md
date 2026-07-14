# AWS Audio Transcription and Near-Miss Search Platform

Version: 1.1

---

# 1. Executive Summary

This solution provides an AWS-native platform for:

- Ingesting WAV audio files
- Performing Speech-to-Text (STT)
- Storing transcripts and timestamps
- Supporting:
  - Exact Match Search
  - Fuzzy Search
  - Optional Semantic Near-Miss Detection
- Preserving original transcript language
- Supporting:
  - en-US
  - zh-CN
  - zh-HK

The platform is designed to:

- Transcribe once
- Search many times
- Scale from hundreds to thousands of recordings
- Minimize AI costs
- Maintain low operational overhead

---

# 2. Scope

## In Scope

- WAV file ingestion
- Speech-to-Text processing
- Transcript storage
- Search API
- Timestamp extraction
- Exact search
- Fuzzy search
- Near-miss detection
- Monitoring
- CI/CD Pipeline

## Out of Scope

- Video transcription
- Real-time streaming transcription
- Custom speech model training
- Translation services
- Contact-center analytics

---

# 3. High-Level Architecture

```text
                     +----------------+
                     |      S3        |
                     |   Audio Files  |
                     +--------+-------+
                              |
                              |
                              v

                     +----------------+
                     | Lambda #1      |
                     | Start STT Job  |
                     +--------+-------+
                              |
                              |
                              v

                     +----------------+
                     | Amazon         |
                     | Transcribe     |
                     +--------+-------+
                              |
                              |
                              v

                     +----------------+
                     | EventBridge    |
                     +--------+-------+
                              |
                              |
                              v

                     +----------------+
                     | Lambda #2      |
                     | Process Result |
                     +--------+-------+
                              |
             +----------------+----------------+
             |                                 |
             |                                 |
             v                                 v

   +----------------------+      +----------------------+
   | Aurora PostgreSQL    |      | OpenSearch           |
   | Source of Truth      |      | Search Engine        |
   +----------------------+      +----------------------+
                                               |
                                               |
                                               v

                                     +------------------+
                                     | Search API       |
                                     +--------+---------+
                                              |
                       +----------------------+-------------------+
                       |                                          |
                       v                                          v

              Exact / Fuzzy Search                    Bedrock (Optional)
                                                      Semantic Re-Ranking
```

---

# 4. Supported Languages

Each WAV file contains one language only.

Supported:

```text
en-US
zh-CN
zh-HK
```

Language is determined from folder structure.

Example:

```text
audio-input/

├── en-US/
├── zh-CN/
└── zh-HK/
```

---

# 5. AWS Services

## S3

Purpose:

```text
Store WAV files
Store transcription output
```

Buckets:

```text
audio-input
transcribe-output
```

---

## Lambda

### Lambda #1

Name:

```text
StartTranscription
```

Purpose:

```text
Start Amazon Transcribe Job
```

Trigger:

```text
S3 Object Created
```

---

### Lambda #2

Name:

```text
ProcessTranscript
```

Purpose:

```text
Parse result
Store data
Index search engine
Use idempotent upsert logic
```

Trigger:

```text
EventBridge
```

---

## Amazon Transcribe

Purpose:

```text
Speech-to-Text conversion
```

Input:

```text
WAV
Language Code
```

Output:

```text
Transcript
Timestamps
Confidence
```

---

## EventBridge

Purpose:

```text
Transcription completion event
```

Target:

```text
ProcessTranscript Lambda
```

Implementation requirement:

- Lambda retries must not create duplicate transcript or segment rows.
- Use deterministic job naming and database uniqueness constraints.

---

## Aurora PostgreSQL

Purpose:

```text
Long-term source of truth
```

Stores:

- Transcripts
- Metadata
- Timestamp segments

---

## OpenSearch

Purpose:

```text
Fast search
```

Supports:

- Phrase search
- Exact match
- Fuzzy match

Implementation requirement:

- Use language-appropriate analyzers for `zh-CN` and `zh-HK` rather than relying only on English tokenization.
- Index segment-level records with stable IDs so OpenSearch updates remain idempotent.

---

## Bedrock (Optional)

Purpose:

```text
Semantic understanding
Near-miss detection
```

Only used for ambiguous searches.

---

# 6. Database Design

## Table: transcripts

```sql
CREATE TABLE transcripts (
    id UUID PRIMARY KEY,
  file_name VARCHAR(255) NOT NULL,
  s3_bucket VARCHAR(255) NOT NULL,
  s3_key TEXT NOT NULL,
  transcribe_job_name VARCHAR(200) NOT NULL UNIQUE,
  language VARCHAR(10) NOT NULL,
  transcript_text TEXT NOT NULL,
  source_etag VARCHAR(128),
  transcript_uri TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (s3_bucket, s3_key, COALESCE(source_etag, ''))
);
```

---

## Table: transcript_segments

```sql
CREATE TABLE transcript_segments (
    id UUID PRIMARY KEY,
  transcript_id UUID NOT NULL,
  segment_index INTEGER NOT NULL,
    start_time NUMERIC,
    end_time NUMERIC,
  text TEXT NOT NULL,
  confidence NUMERIC,
  created_at TIMESTAMPTZ NOT NULL,
  UNIQUE (transcript_id, segment_index)
);
```

---

## Recommended Indexes

```sql
CREATE INDEX idx_language
ON transcripts(language);

CREATE INDEX idx_transcript
ON transcript_segments(transcript_id);

CREATE INDEX idx_segments_time_range
ON transcript_segments(transcript_id, start_time, end_time);
```

Notes:

- `transcribe_job_name` provides an idempotent link between Transcribe and Aurora.
- `segment_index` preserves deterministic ordering for replay-safe upserts.

---

# 7. OpenSearch Setup

## Domain

```text
audio-search
```

## Instance Type

```text
t3.small.search
```

## Nodes

```text
2
```

---

## Indices

```text
transcripts-en
transcripts-zh-cn
transcripts-zh-hk
```

---

## Example Document

```json
{
  "segment_id":"4b5c2f2a5d4e41a19df25dfe5df0e4f1",
  "transcript_id":"0a9f9df87f8f4c45a3dc1bbf0c5f8942",
  "file":"call001.wav",
  "language":"en-US",
  "start_time":120,
  "end_time":127,
  "text":"Project Alpha budget approved"
}
```

---

# 8. Search Flow

## Level 1 - Exact Match

Input:

```text
Project Alpha
```

Output:

```text
Project Alpha
```

Confidence:

```text
100%
```

---

## Level 2 - Fuzzy Match

Input:

```text
Project Alpha
```

Potential Matches:

```text
Project Alfa
Project Apha
Project Alpher
```

Confidence:

```text
85%-99%
```

---

## Level 3 - Semantic Search

Input:

```text
customer complaint
```

Potential Match:

```text
client dissatisfaction
```

Requires:

```text
Bedrock
```

---

# 9. Bedrock Usage Strategy

## Do Not

```text
Every Query
 ↓
Bedrock
```

Expensive.

---

## Recommended

```text
Search
 ↓
OpenSearch
 ↓
Top 20 Candidates
 ↓
Bedrock
 ↓
Re-rank
```

---

## Bedrock Invocation Conditions

Invoke Bedrock only when:

- No exact match exists
- Fuzzy score below threshold
- User explicitly requests semantic search
- Phrase contains business meaning

Examples:

```text
customer complaint
cloud migration
budget approval
```

---

# 10. Search API

## Endpoint

```http
POST /search
```

---

## Request

```json
{
  "query":"Project Alpha",
  "mode":"fuzzy"
}
```

Modes:

```text
exact
fuzzy
semantic
```

---

## Response

```json
{
  "results":[
    {
      "transcriptId":"0a9f9df87f8f4c45a3dc1bbf0c5f8942",
      "segmentId":"4b5c2f2a5d4e41a19df25dfe5df0e4f1",
      "file":"call001.wav",
      "language":"en-US",
      "timestamp":"00:02:05",
      "matchType":"fuzzy",
      "matchedText":"Project Alpha budget approved",
      "confidence":0.98
    }
  ]
}
```

Confidence guidance:

- Exact match confidence is deterministic.
- Fuzzy confidence comes from OpenSearch scoring normalized by application logic.
- Semantic confidence must be kept separate from lexical scores to avoid mixing incompatible scales.

---

# 11. IAM Setup

## AudioProcessorRole

Permissions:

```text
Scoped S3 GetObject on input bucket
Scoped S3 PutObject on output bucket
Transcribe StartTranscriptionJob
CloudWatch Logs write permissions
```

---

## SearchRole

Permissions:

```text
OpenSearch Access
Aurora Access
Bedrock InvokeModel
```

Use least-privilege IAM policies rather than broad managed policies.

---

# 12. Monitoring

## CloudWatch Metrics

Monitor:

```text
Lambda Errors
Transcribe Failures
API Errors
Search Latency
Aurora CPU
OpenSearch Health
```

---

## CloudWatch Alarms

Alert When:

```text
Lambda Failure > 5
Transcribe Failure > 0
Aurora CPU > 80%
OpenSearch Cluster != Green
```

---

# 13. Optional CI/CD Pipeline

## Objective

Automate:

- Infrastructure deployment
- Lambda deployment
- Search API deployment
- Environment promotion

---

# CI/CD Architecture

```text
Git Repository
      |
      v

Code Commit / Pull Request
      |
      v

GitHub Actions / CodePipeline
      |
      +--------------------------+
      |                          |
      v                          v

Terraform Validation      Unit Tests
      |                          |
      +------------+-------------+
                   |
                   v

           Build Artifacts
                   |
                   v

         Deploy to Dev
                   |
                   v

          Smoke Testing
                   |
                   v

         Manual Approval
                   |
                   v

         Deploy to UAT
                   |
                   v

         Deploy to Prod
```

---

# Recommended Repository Structure

```text
repo/

├── terraform/
│   ├── s3/
│   ├── lambda/
│   ├── aurora/
│   ├── opensearch/
│   └── iam/
│
├── lambdas/
│   ├── StartTranscription/
│   └── ProcessTranscript/
│
├── api/
│
├── docs/
│
└── pipelines/
```

---

# Infrastructure as Code

Recommended:

```text
Terraform
```

Manage:

- S3
- Lambda
- IAM
- EventBridge
- Aurora
- OpenSearch

No manual deployment.

---

# Git Branch Strategy

```text
main
develop
feature/*
hotfix/*
```

---

# Deployment Flow

## Feature Development

```text
feature branch
  ↓
Pull Request
  ↓
Code Review
  ↓
Merge develop
```

---

## UAT Release

```text
develop
  ↓
Deploy DEV
  ↓
User Testing
```

---

## Production Release

```text
main
 ↓
Approval
 ↓
Production Deployment
```

---

# Secrets Management

Store:

```text
DB Passwords
API Keys
Bedrock Config
```

in:

```text
AWS Secrets Manager
```

Never commit secrets to Git.

---

# 14. User Acceptance Testing

## Test 1

Upload:

```text
call001.wav
```

Verify:

```text
Transcription completed
```

---

## Test 2

Search:

```text
Project Alpha
```

Verify:

```text
Timestamp returned
```

---

## Test 3

Search:

```text
Project Alfa
```

Verify:

```text
Fuzzy match returned
```

---

## Test 4

Search:

```text
customer complaint
```

Verify:

```text
Semantic match returned
```

---

# 15. Cost Estimation

Assumptions:

```text
500 WAV Files
30 Minutes Each
15,000 Total Minutes
```

---

## One-Time Cost

### Amazon Transcribe

```text
~ USD 360
```

---

## Monthly Operating Cost

### Aurora PostgreSQL

```text
USD 50-100
```

### OpenSearch

```text
USD 60-90
```

### S3

```text
USD 2-10
```

### Lambda + Logs

```text
< USD 10
```

### Optional Bedrock

```text
USD 10-50
```

---

## Estimated Monthly Total

Without Bedrock:

```text
USD 120-210
```

With Bedrock:

```text
USD 130-260
```

---

# 16. Production Readiness Checklist

- [ ] S3 Encryption Enabled
- [ ] Aurora Backup Enabled
- [ ] OpenSearch Snapshot Policy Enabled
- [ ] CloudWatch Monitoring Enabled
- [ ] CloudWatch Alarms Configured
- [ ] Secrets Manager Configured
- [ ] IAM Least Privilege Applied
- [ ] Lambda Retry Policy Configured
- [ ] Dead Letter Queue Configured
- [ ] CI/CD Configured
- [ ] UAT Completed
- [ ] Production Cutover Approved

---

# 17. Success Criteria

The platform is complete when:

- WAV files are automatically processed.
- STT is fully automated.
- Original language is preserved.
- Exact matching works.
- Fuzzy matching works.
- Near-miss detection works when enabled.
- Search results include timestamps.
- Search latency remains under 5 seconds.
- Audio is transcribed only once.
- CI/CD deployment is automated.
- Monthly operating cost remains within budget.