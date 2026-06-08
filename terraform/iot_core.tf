// IoT Core resources: Thing, Policy, Certificate, Topic Rule → SQS

locals {
  iot_role_arn = var.iot_role_arn != "" ? var.iot_role_arn : aws_iam_role.iot_topic_rule_role[0].arn
}

# En AWS Learner Lab NO se pueden crear políticas IAM administradas.
# LabRole ya tiene permisos suficientes (vía SCP de Learner Lab) para
# todas las acciones requeridas: sqs:SendMessage, dynamodb:PutItem,
# dynamodb:UpdateItem, s3:PutObject, s3:GetObject, logs:CreateLogStream,
# logs:PutLogEvents. Por lo tanto no se necesita crear ni adjuntar
# políticas adicionales.

# Thing
resource "aws_iot_thing" "sensor" {
  name = "${var.iot_thing_name}-${var.environment}"

  attributes = {
    project = "IoT-Project"
    env     = var.environment
  }
}

# Policy para los dispositivos (permitir publish/subscribe/connect/receive a topics)
resource "aws_iot_policy" "device_policy" {
  name   = "iot-device-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        # Connect: el recurso debe ser tipo 'client'
        Effect = "Allow",
        Action = ["iot:Connect"],
        Resource = [
          "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:client/*"
        ]
      },
      {
        # Publish y Receive: el recurso debe ser tipo 'topic'
        Effect = "Allow",
        Action = ["iot:Publish", "iot:Receive"],
        Resource = [
          "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/*"
        ]
      },
      {
        # Subscribe: el recurso DEBE ser tipo 'topicfilter' (no 'topic')
        # Sin esto, AWS IoT Core rechaza/desconecta silenciosamente al cliente
        Effect = "Allow",
        Action = ["iot:Subscribe"],
        Resource = [
          "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topicfilter/*"
        ]
      }
    ]
  })
}

# NOTE: Device certificates (mutual-TLS keys) are intentionally not created
# by Terraform here because the provider does not support creating key pairs
# in all environments. Provision device certificates out-of-band and attach
# them manually or via a provisioning process. The `aws_iot_policy` above
# is available to be attached to device certificates when provisioning is done.

# IAM role for IoT Topic Rule to send messages to SQS
# Solo se crea si no se pasa var.iot_role_arn
resource "aws_iam_role" "iot_topic_rule_role" {
  count = var.iot_role_arn == "" ? 1 : 0
  name  = "iot-topic-rule-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = { Service = "iot.amazonaws.com" },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "iot_topic_rule_policy" {
  count = var.iot_role_arn == "" ? 1 : 0
  name  = "iot-topic-rule-policy-${var.environment}"
  role  = aws_iam_role.iot_topic_rule_role[0].id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "IoTToSQS"
        Effect = "Allow",
        Action = ["sqs:SendMessage"],
        Resource = [aws_sqs_queue.sensor_queue.arn]
      },
      {
        Sid    = "IoTToDynamoDB"
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        Resource = [aws_dynamodb_table.sensor_data.arn]
      },
      {
        Sid    = "IoTToS3"
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ],
        Resource = ["${aws_s3_bucket.sensor_archive.arn}/*"]
      },
      {
        Sid    = "IoTToCloudWatch"
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = [
          aws_cloudwatch_log_group.iot_logs.arn,
          "${aws_cloudwatch_log_group.iot_logs.arn}:*"
        ]
      }
    ]
  })
}

# Topic Rule 1: enrutar mensajes desde 'sensors/+' hacia la cola SQS
# y también registrar cada mensaje en CloudWatch Logs para visibilidad.
resource "aws_iot_topic_rule" "to_sqs" {
  name        = "iot_rule_to_sqs_${replace(var.environment, "-", "_")}"
  sql         = "SELECT * FROM 'sensors/+'"
  sql_version = "2016-03-23"
  enabled     = true

  sqs {
    role_arn   = local.iot_role_arn
    queue_url  = aws_sqs_queue.sensor_queue.url
    use_base64 = false
  }

  cloudwatch_logs {
    role_arn = local.iot_role_arn
    log_group_name = aws_cloudwatch_log_group.iot_logs.name
  }
}

# Topic Rule 2: enrutar mensajes desde 'sensors/+' hacia DynamoDB (Hot Data)
resource "aws_iot_topic_rule" "to_dynamodb" {
  name        = "iot_rule_to_dynamodb_${replace(var.environment, "-", "_")}"
  sql         = "SELECT *, timestamp() as ts FROM 'sensors/+'"
  sql_version = "2016-03-23"
  enabled     = true

  dynamodb {
    role_arn        = local.iot_role_arn
    table_name      = aws_dynamodb_table.sensor_data.name
    hash_key_field  = "sensor_id"
    hash_key_value  = "$${sensor_id}"
    range_key_field = "timestamp"
    range_key_value = "$${ts}"
    operation       = "INSERT"
  }
}

# Topic Rule 3: enrutar mensajes desde 'sensors/+' hacia S3 (Cold Data)
# Los archivos se guardan con particionamiento por fecha: sensors/YYYY/MM/DD/HHmm-UUID.json
resource "aws_iot_topic_rule" "to_s3" {
  name        = "iot_rule_to_s3_${replace(var.environment, "-", "_")}"
  sql         = "SELECT * FROM 'sensors/+'"
  sql_version = "2016-03-23"
  enabled     = true

  s3 {
    role_arn   = local.iot_role_arn
    bucket_name = aws_s3_bucket.sensor_archive.id
    key        = "sensors/$${timestamp()}-$${clientId()}.json"
    canned_acl = "private"
  }
}
