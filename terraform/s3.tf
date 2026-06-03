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
