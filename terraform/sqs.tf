# SQS Queue para mensajes
resource "aws_sqs_queue" "sensor_queue" {
  name                      = "iot-sensor-queue-${var.environment}"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 345600
  receive_wait_time_seconds = 0

  tags = {
    Name = "IoT Sensor Queue"
  }
}
