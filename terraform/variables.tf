variable "aws_region" {
  description = "AWS region for this stack."
  type        = string
}

variable "project_name" {
  description = "Base name for AWS resources."
  type        = string
  default     = "audio-search"
}

variable "environment" {
  description = "Deployment environment label."
  type        = string
  default     = "dev"
}

variable "input_bucket_name" {
  description = "Globally unique S3 bucket name for uploaded audio."
  type        = string
}

variable "transcribe_output_bucket_name" {
  description = "Globally unique S3 bucket name for Transcribe output."
  type        = string
}

variable "transcribe_output_prefix" {
  description = "Prefix used by Transcribe when writing output objects."
  type        = string
  default     = "jobs/"
}

variable "transcribe_job_name_prefix" {
  description = "Prefix added to deterministic Transcribe job names."
  type        = string
  default     = "audio-search"
}

variable "lambda_runtime" {
  description = "Python runtime used by the Lambda functions."
  type        = string
  default     = "python3.12"
}

variable "lambda_architectures" {
  description = "Lambda CPU architecture list."
  type        = list(string)
  default     = ["x86_64"]
}

variable "transcript_output_table" {
  description = "Placeholder environment variable for the ProcessTranscript Lambda."
  type        = string
  default     = "not-configured"
}

variable "tags" {
  description = "Additional tags for all AWS resources."
  type        = map(string)
  default     = {}
}