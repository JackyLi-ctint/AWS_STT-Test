# AWS Setup

This setup provisions the AWS resources needed for the current implementation slice:

- input S3 bucket for WAV uploads
- output S3 bucket for Amazon Transcribe results
- `StartTranscription` Lambda
- `ProcessTranscript` Lambda
- EventBridge rule for completed Transcribe jobs
- IAM roles and CloudWatch log groups

It does not yet provision Aurora PostgreSQL or OpenSearch because the current code only logs normalized transcript rows and segments.

## Prerequisites

- AWS account and IAM permissions for S3, Lambda, EventBridge, CloudWatch Logs, IAM, and Transcribe
- AWS CLI configured locally
- Terraform 1.6+
- PowerShell 5.1+
- GitHub repository with Actions enabled

## 1. Configure AWS Credentials

Use one of these approaches before running Terraform:

- `aws configure`
- environment variables such as `AWS_PROFILE` or `AWS_ACCESS_KEY_ID`

Confirm the target account:

```powershell
aws sts get-caller-identity
```

## 2. Enable CI Auto Build and Test (GitHub Actions)

Recommended: use GitHub Actions as the default build and test gate for pull requests and branch pushes.

The repository includes a workflow at `.github/workflows/ci.yml` that runs:

- unit tests (`python -m unittest discover -s tests -p "test_*.py"`)
- syntax compilation check (`python -m compileall lambdas tests`)
- Lambda package build (`.\scripts\build_lambda_packages.ps1`)
- artifact upload for generated ZIP packages

Trigger scope:

- pull requests to `main` and `develop`
- pushes to `main`, `develop`, and `feature/*`

This keeps Terraform deployment gated behind a passing CI run.

## 3. Build Lambda Packages Locally (Optional)

From the repository root:

```powershell
.\scripts\build_lambda_packages.ps1
```

This creates:

- `build/start_transcription.zip`
- `build/process_transcript.zip`

## 4. Prepare Terraform Variables

Copy the example file and fill in unique bucket names:

```powershell
Copy-Item .\terraform\terraform.tfvars.example .\terraform\terraform.tfvars
```

Required values to review:

- `aws_region`
- `input_bucket_name`
- `transcribe_output_bucket_name`
- `tags`

## 5. Deploy the Current Slice

Recommended promotion sequence:

1. Open PR and let GitHub Actions CI pass.
2. Merge to target branch.
3. Run Terraform deployment from a trusted environment.

```powershell
Set-Location .\terraform
terraform init
terraform plan
terraform apply
```

## 6. Smoke Test

Upload a WAV file to the input bucket using one of the supported language prefixes:

```text
en-US/example.wav
zh-CN/example.wav
zh-HK/example.wav
```

Then verify:

- the `StartTranscription` Lambda is invoked
- Amazon Transcribe creates a job
- transcript JSON appears in the output bucket
- the `ProcessTranscript` Lambda logs normalized transcript and segment records

## 7. Current Limits

- `ProcessTranscript` does not persist to Aurora yet.
- `ProcessTranscript` does not index to OpenSearch yet.
- No API is deployed in this stack yet.

Those are the next AWS slices after this bootstrap deploy succeeds.

## 8. Forward Plan for CI/CD

After CI is stable, extend the workflow in phases:

1. Add Terraform formatting and validation checks. This is implemented as the `Terraform PR Checks` workflow.
2. Add `terraform plan` on pull requests.
3. Add environment deployment workflows (dev auto, uat/prod with approvals).
4. Add post-deploy smoke test automation.
