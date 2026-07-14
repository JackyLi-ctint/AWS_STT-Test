# AWS Audio Search Platform

This repository contains the first implementation slice for the audio transcription and search platform described in the architecture document.

Implemented in this slice:

- `StartTranscription` Lambda for S3-triggered Transcribe job creation
- `ProcessTranscript` Lambda for Transcribe result normalization
- shared transcript parsing utilities
- an idempotent PostgreSQL schema draft
- Terraform scaffold for S3, Lambda, EventBridge, CloudWatch Logs, and IAM
- PowerShell build script for Lambda deployment packages
- unit tests for the deterministic parsing logic

## Layout

```text
lambdas/
  StartTranscription/
  ProcessTranscript/
  shared/
terraform/
scripts/
docs/
sql/
tests/
```

## Local Validation

```powershell
python -m unittest discover -s tests -p "test_*.py"
python -m compileall lambdas tests
.\scripts\build_lambda_packages.ps1
```

## AWS Setup Flow

1. Build the Lambda packages with `.\scripts\build_lambda_packages.ps1`.
2. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and fill in unique bucket names.
3. Run `terraform init`, `terraform plan`, and `terraform apply` inside `terraform/`.
4. Upload a test WAV file into the input bucket under `en-US/`, `zh-CN/`, or `zh-HK/`.

Detailed AWS steps are in `docs/aws_setup.md`.

## Environment Variables

### StartTranscription

- `TRANSCRIBE_OUTPUT_BUCKET`
- `TRANSCRIBE_OUTPUT_PREFIX` (optional, default: `jobs/`)
- `TRANSCRIBE_JOB_NAME_PREFIX` (optional, default: `audio-search`)

### ProcessTranscript

- `TRANSCRIPT_OUTPUT_TABLE` (optional, logging placeholder for future persistence)

The current implementation normalizes transcript payloads and logs structured records. Aurora persistence and OpenSearch indexing are still the next implementation slice, so the AWS scaffold provisions only the services needed for the current code path.