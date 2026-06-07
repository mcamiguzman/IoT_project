// IoT Core resources: Thing, Policy, Certificate, Topic Rule → SQS

locals {
  iot_role_arn = var.iot_role_arn != "" ? var.iot_role_arn : aws_iam_role.iot_topic_rule_role[0].arn
}

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
        Effect = "Allow",
        Action = [
          "iot:Publish",
          "iot:Subscribe",
          "iot:Connect",
          "iot:Receive"
        ],
        Resource = [
          "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/*",
          "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:client/*"
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
        Effect = "Allow",
        Action = ["sqs:SendMessage"],
        Resource = [aws_sqs_queue.sensor_queue.arn]
      },
      {
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

# Política para el rol existente (LabRole) cuando se pasa por variable
data "aws_iam_policy_document" "iot_topic_rule_extra" {
  count = var.iot_role_arn != "" ? 1 : 0

  statement {
    sid    = "IoTToSQS"
    effect = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.sensor_queue.arn]
  }

  statement {
    sid    = "IoTToCloudWatch"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      aws_cloudwatch_log_group.iot_logs.arn,
      "${aws_cloudwatch_log_group.iot_logs.arn}:*"
    ]
  }
}

resource "aws_iam_policy" "iot_topic_rule_extra" {
  count      = var.iot_role_arn != "" ? 1 : 0
  name       = "iot-topic-rule-extra-${var.environment}"
  policy     = data.aws_iam_policy_document.iot_topic_rule_extra[0].json
  tags       = {}
  tags_all   = {}
}

resource "aws_iam_role_policy_attachment" "iot_topic_rule_extra_attach" {
  count      = var.iot_role_arn != "" ? 1 : 0
  role       = split("/", var.iot_role_arn)[length(split("/", var.iot_role_arn)) - 1]
  policy_arn = aws_iam_policy.iot_topic_rule_extra[0].arn
}

# Topic Rule: enrutar mensajes desde 'sensors/#' hacia la cola SQS
# y también registrar cada mensaje en CloudWatch Logs para visibilidad.
resource "aws_iot_topic_rule" "to_sqs" {
  name        = "iot_rule_to_sqs_${replace(var.environment, "-", "_")}"
  sql         = "SELECT * FROM 'sensors/#'"
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