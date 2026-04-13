output "raw_bucket_name" {
  value = aws_s3_bucket.raw.bucket
}

output "processed_bucket_name" {
  value = aws_s3_bucket.processed.bucket
}

output "glue_job_name" {
  value = aws_glue_job.etl.name
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.pipeline_alerts.arn
}
