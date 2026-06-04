# DynamoDB Table para hot data
resource "aws_dynamodb_table" "sensor_data" {
  name         = "sensor-data-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sensor_id"
  range_key    = "timestamp"

  # Habilitar streams para trigger de Lambda (temperature_alert)
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "sensor_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  ttl {
    attribute_name = "expiration"
    enabled        = true
  }

  tags = {
    Name = "IoT Sensor Data Table"
  }
}
