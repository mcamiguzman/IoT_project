# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "iot_logs" {
  name              = "/aws/iot/sensors/${var.environment}"
  retention_in_days = 14

  tags = {
    Name = "IoT Sensors Logs"
  }
}
