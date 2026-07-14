output "input_bucket_name" {
  description = "S3 bucket receiving uploaded WAV files."
  value       = aws_s3_bucket.input.bucket
}

output "transcribe_output_bucket_name" {
  description = "S3 bucket receiving Amazon Transcribe output."
  value       = aws_s3_bucket.transcribe_output.bucket
}

output "start_transcription_function_name" {
  description = "Lambda that starts Amazon Transcribe jobs."
  value       = aws_lambda_function.start_transcription.function_name
}

output "process_transcript_function_name" {
  description = "Lambda that normalizes completed Amazon Transcribe jobs."
  value       = aws_lambda_function.process_transcript.function_name
}

output "transcribe_completed_rule_name" {
  description = "EventBridge rule that reacts to completed transcription jobs."
  value       = aws_cloudwatch_event_rule.transcribe_completed.name
}