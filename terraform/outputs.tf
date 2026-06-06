output "dynamodb_table_name" {
  value       = aws_dynamodb_table.sensor_data.name
  description = "DynamoDB table name"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.sensor_archive.id
  description = "S3 bucket name for sensor archive"
}

output "sqs_queue_url" {
  value       = aws_sqs_queue.sensor_queue.url
  description = "SQS queue URL"
}

output "lambda_role_arn" {
  value       = local.lambda_role_arn
  description = "Lambda IAM role ARN (usa LabRole en Learner Lab)"
}

output "cloudwatch_log_group" {
  value       = aws_cloudwatch_log_group.iot_logs.name
  description = "CloudWatch log group name"
}

output "lambda_process_s3_arn" {
  value       = aws_lambda_function.process_s3.arn
  description = "Lambda function ARN for processing S3 files"
}

output "lambda_temperature_alert_arn" {
  value       = aws_lambda_function.temperature_alert.arn
  description = "Lambda function ARN for temperature alerts"
}

output "lambda_cloudwatch_logs_arn" {
  value       = aws_lambda_function.cloudwatch_logs.arn
  description = "Lambda function ARN for CloudWatch logs"
}

output "iot_thing_name" {
  value       = aws_iot_thing.sensor.name
  description = "Nombre del Thing generado en AWS IoT Core"
}

output "iot_policy_name" {
  value       = aws_iot_policy.device_policy.name
  description = "Nombre de la policy de IoT para dispositivos"
}

output "iot_topic_rule" {
  value       = aws_iot_topic_rule.to_sqs.name
  description = "Nombre de la IoT Topic Rule que enruta mensajes a SQS"
}
