# S3 Bucket para almacenar datos históricos
resource "aws_s3_bucket" "sensor_archive" {
  bucket = "iot-sensor-archive-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "IoT Sensor Archive"
  }
}

resource "aws_s3_bucket_versioning" "sensor_archive" {
  bucket = aws_s3_bucket.sensor_archive.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "sensor_archive" {
  bucket = aws_s3_bucket.sensor_archive.id

  rule {
    id     = "transition_to_glacier"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# S3 bucket para resultados de Athena
resource "aws_s3_bucket" "athena_results" {
  bucket = "iot-athena-results-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "IoT Athena Query Results"
  }
}

# Glue Database para catálogo de Athena
resource "aws_glue_catalog_database" "sensor_history" {
  name = "sensor_history_${var.environment}"

  description = "Database for sensor historical data queries via Athena"
}

# Athena Workgroup para ejecutar queries
resource "aws_athena_workgroup" "sensor_queries" {
  name            = "sensor-queries-${var.environment}"
  force_destroy   = true

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/queries/"
    }

    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
  }

  tags = {
    Name = "IoT Sensor Query Workgroup"
  }
}
