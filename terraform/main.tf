locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_s3_bucket" "input" {
  bucket = var.input_bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  bucket = aws_s3_bucket.input.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "input" {
  bucket                  = aws_s3_bucket.input.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "transcribe_output" {
  bucket = var.transcribe_output_bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "transcribe_output" {
  bucket = aws_s3_bucket.transcribe_output.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "transcribe_output" {
  bucket = aws_s3_bucket.transcribe_output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "transcribe_output" {
  bucket                  = aws_s3_bucket.transcribe_output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "transcribe_input_bucket" {
  statement {
    sid    = "AllowTranscribeReadInput"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["transcribe.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.input.arn}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "transcribe_input_bucket" {
  bucket = aws_s3_bucket.input.id
  policy = data.aws_iam_policy_document.transcribe_input_bucket.json
}

data "aws_iam_policy_document" "transcribe_output_bucket" {
  statement {
    sid    = "AllowTranscribeWriteOutput"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["transcribe.amazonaws.com"]
    }

    actions = [
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.transcribe_output.arn}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "transcribe_output_bucket" {
  bucket = aws_s3_bucket.transcribe_output.id
  policy = data.aws_iam_policy_document.transcribe_output_bucket.json
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "start_transcription" {
  name               = "${local.name_prefix}-start-transcription"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "start_transcription" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "transcribe:StartTranscriptionJob",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "start_transcription" {
  name   = "${local.name_prefix}-start-transcription"
  role   = aws_iam_role.start_transcription.id
  policy = data.aws_iam_policy_document.start_transcription.json
}

resource "aws_iam_role" "process_transcript" {
  name               = "${local.name_prefix}-process-transcript"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "process_transcript" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*",
    ]
  }
}

resource "aws_iam_role_policy" "process_transcript" {
  name   = "${local.name_prefix}-process-transcript"
  role   = aws_iam_role.process_transcript.id
  policy = data.aws_iam_policy_document.process_transcript.json
}

resource "aws_cloudwatch_log_group" "start_transcription" {
  name              = "/aws/lambda/${local.name_prefix}-start-transcription"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "process_transcript" {
  name              = "/aws/lambda/${local.name_prefix}-process-transcript"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_lambda_function" "start_transcription" {
  function_name    = "${local.name_prefix}-start-transcription"
  description      = "Starts Amazon Transcribe jobs for uploaded WAV audio."
  role             = aws_iam_role.start_transcription.arn
  filename         = "${path.module}/../build/start_transcription.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/start_transcription.zip")
  handler          = "lambdas.StartTranscription.handler.lambda_handler"
  runtime          = var.lambda_runtime
  architectures    = var.lambda_architectures
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      TRANSCRIBE_OUTPUT_BUCKET   = aws_s3_bucket.transcribe_output.bucket
      TRANSCRIBE_OUTPUT_PREFIX   = var.transcribe_output_prefix
      TRANSCRIBE_JOB_NAME_PREFIX = var.transcribe_job_name_prefix
    }
  }

  depends_on = [aws_cloudwatch_log_group.start_transcription]
  tags       = local.common_tags
}

resource "aws_lambda_function" "process_transcript" {
  function_name    = "${local.name_prefix}-process-transcript"
  description      = "Normalizes completed Amazon Transcribe output into structured records."
  role             = aws_iam_role.process_transcript.arn
  filename         = "${path.module}/../build/process_transcript.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/process_transcript.zip")
  handler          = "lambdas.ProcessTranscript.handler.lambda_handler"
  runtime          = var.lambda_runtime
  architectures    = var.lambda_architectures
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      TRANSCRIPT_OUTPUT_TABLE = var.transcript_output_table
    }
  }

  depends_on = [aws_cloudwatch_log_group.process_transcript]
  tags       = local.common_tags
}

resource "aws_lambda_permission" "allow_s3_start_transcription" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_transcription.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input.arn
}

resource "aws_s3_bucket_notification" "input" {
  bucket = aws_s3_bucket.input.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.start_transcription.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".wav"
  }

  depends_on = [aws_lambda_permission.allow_s3_start_transcription]
}

resource "aws_cloudwatch_event_rule" "transcribe_completed" {
  name        = "${local.name_prefix}-transcribe-completed"
  description = "Invokes ProcessTranscript when Amazon Transcribe completes a job."

  event_pattern = jsonencode({
    source      = ["aws.transcribe"]
    detail-type = ["Transcribe Job State Change"]
    detail = {
      TranscriptionJobStatus = ["COMPLETED"]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "process_transcript" {
  rule      = aws_cloudwatch_event_rule.transcribe_completed.name
  target_id = "process-transcript"
  arn       = aws_lambda_function.process_transcript.arn
}

resource "aws_lambda_permission" "allow_eventbridge_process_transcript" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_transcript.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.transcribe_completed.arn
}