locals {
  # Usar rol especificado o rol por defecto del laboratorio
  lambda_role_arn = var.lambda_role_arn != "" ? var.lambda_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/voclabs"
}

# Data archive para localizar los archivos zip de las Lambdas
data "archive_file" "process_s3_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/process_s3"
  output_path = "${path.module}/../lambdas/process_s3.zip"
}

data "archive_file" "temperature_alert_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/temperature_alert"
  output_path = "${path.module}/../lambdas/temperature_alert.zip"
}

data "archive_file" "cloudwatch_logs_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/cloudwatch_logs"
  output_path = "${path.module}/../lambdas/cloudwatch_logs.zip"
}

# Lambda 1: Procesar S3 → PostgreSQL
resource "aws_lambda_function" "process_s3" {
  filename      = data.archive_file.process_s3_zip.output_path
  function_name = "iot-process-s3-${var.environment}"
  role          = local.lambda_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60

  source_code_hash = data.archive_file.process_s3_zip.output_base64sha256

  environment {
    variables = {
      DB_HOST     = "postgres"  # Cambiar según tu endpoint RDS
      DB_NAME     = "iot_db"
      DB_USER     = "postgres"
      DB_PASSWORD = "postgres"  # Usar AWS Secrets Manager en producción
    }
  }

  tags = {
    Name = "IoT Process S3 Lambda"
  }
}

# Permiso S3 para invocar Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_s3.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.sensor_archive.arn
}

# Notificación de S3 para invocar Lambda
resource "aws_s3_bucket_notification" "sensor_archive_lambda" {
  bucket = aws_s3_bucket.sensor_archive.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_s3.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Lambda 2: Alerta de Temperatura
resource "aws_lambda_function" "temperature_alert" {
  filename      = data.archive_file.temperature_alert_zip.output_path
  function_name = "iot-temperature-alert-${var.environment}"
  role          = local.lambda_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30

  source_code_hash = data.archive_file.temperature_alert_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE  = aws_dynamodb_table.sensor_data.name
      SQS_QUEUE_URL   = aws_sqs_queue.sensor_queue.url
      TEMP_THRESHOLD  = 30
    }
  }

  tags = {
    Name = "IoT Temperature Alert Lambda"
  }
}

# Event source mapping: DynamoDB Stream → Lambda
resource "aws_lambda_event_source_mapping" "dynamodb_to_lambda" {
  event_source_arn  = aws_dynamodb_table.sensor_data.stream_arn
  function_name     = aws_lambda_function.temperature_alert.function_name
  enabled           = true
  batch_size        = 100
  starting_position = "LATEST"
}

# Lambda 3: CloudWatch Logs
resource "aws_lambda_function" "cloudwatch_logs" {
  filename      = data.archive_file.cloudwatch_logs_zip.output_path
  function_name = "iot-cloudwatch-logs-${var.environment}"
  role          = local.lambda_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30

  source_code_hash = data.archive_file.cloudwatch_logs_zip.output_base64sha256

  environment {
    variables = {
      LOG_GROUP     = aws_cloudwatch_log_group.iot_logs.name
      SQS_QUEUE_URL = aws_sqs_queue.sensor_queue.url
    }
  }

  tags = {
    Name = "IoT CloudWatch Logs Lambda"
  }
}

# Event source mapping: SQS → Lambda
resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.sensor_queue.arn
  function_name    = aws_lambda_function.cloudwatch_logs.function_name
  enabled          = true
  batch_size       = 10
}
