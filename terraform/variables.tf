variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "lambda_role_arn" {
  description = "ARN del rol IAM existente para Lambda (requerido en AWS Learner Lab)"
  type        = string
  default     = ""  # Dejar vacío si usas el rol por defecto de tu cuenta
}

variable "iot_role_arn" {
  description = "ARN del rol IAM existente que usará AWS IoT Topic Rules para acciones. Requerido en AWS Learner Lab cuando no puedes crear roles IAM."
  type        = string
  default     = ""
}

variable "iot_thing_name" {
  description = "Nombre base para los Things de IoT"
  type        = string
  default     = "sensor-thing"
}

variable "dynamodb_billing_mode" {
  description = "Modo de facturación para DynamoDB"
  type        = string
  default     = "PAY_PER_REQUEST"
}