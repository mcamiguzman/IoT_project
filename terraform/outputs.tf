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

# ============================================================================
# OUTPUTS AGREGADOS: IoT ENDPOINT, RDS, TOPIC RULES
# ============================================================================

output "iot_endpoint" {
  value       = data.aws_caller_identity.current.account_id != "" ? "PLACEHOLDER" : "ERROR"
  description = "AWS IoT endpoint (REEMPLAZAR CON VALOR REAL)"
  # NOTA: AWS Terraform provider no expone el endpoint directamente
  # Usar: aws iot describe-endpoint --endpoint-type iot:Data-ATS --query endpointAddress --output text
}

output "iot_endpoint_command" {
  value       = "aws iot describe-endpoint --endpoint-type iot:Data-ATS --region ${var.aws_region} --query endpointAddress --output text"
  description = "Comando para obtener el IoT endpoint"
}

# Outputs de RDS (desde database.tf)
output "rds_endpoint" {
  value       = aws_db_instance.sensors.endpoint
  description = "RDS endpoint (host:port)"
}

output "rds_address" {
  value       = aws_db_instance.sensors.address
  description = "RDS hostname"
}

output "rds_port" {
  value       = aws_db_instance.sensors.port
  description = "RDS port"
}

output "rds_database" {
  value       = aws_db_instance.sensors.db_name
  description = "RDS database name"
}

output "rds_username" {
  value       = aws_db_instance.sensors.username
  description = "RDS master username"
}

output "rds_credentials_file" {
  value       = local_file.rds_credentials.filename
  description = "Archivo con credenciales RDS (JSON)"
}

# Topic Rules adicionales
output "iot_topic_rule_dynamodb" {
  value       = aws_iot_topic_rule.to_dynamodb.name
  description = "Topic Rule que enruta mensajes a DynamoDB"
}

output "iot_topic_rule_s3" {
  value       = aws_iot_topic_rule.to_s3.name
  description = "Topic Rule que enruta mensajes a S3"
}

# ============================================================================
# RESUMEN DE RECURSOS CLAVE
# ============================================================================

output "resources_summary" {
  value = {
    dynamodb_table      = aws_dynamodb_table.sensor_data.name
    s3_bucket           = aws_s3_bucket.sensor_archive.id
    sqs_queue_url       = aws_sqs_queue.sensor_queue.url
    rds_endpoint        = aws_db_instance.sensors.endpoint
    cloudwatch_log_group = aws_cloudwatch_log_group.iot_logs.name
    iot_thing           = aws_iot_thing.sensor.name
  }
  description = "Resumen de recursos principales creados"
}
