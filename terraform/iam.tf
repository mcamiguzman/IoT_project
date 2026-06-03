# IAM Role para Lambda
# NOTA: En AWS Learner Lab, no puedes crear roles IAM.
# Se debe usar un rol pre-existente. Especifica el ARN en la variable lambda_role_arn
# o descomenta esto si tienes permisos en tu cuenta AWS.

# resource "aws_iam_role" "lambda_role" {
#   name = "iot-lambda-role-${var.environment}"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "lambda.amazonaws.com"
#         }
#       }
#     ]
#   })
# }

# Policy para Lambda
# resource "aws_iam_role_policy" "lambda_policy" {
#   name = "iot-lambda-policy-${var.environment}"
#   role = aws_iam_role.lambda_role.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "dynamodb:PutItem",
#           "dynamodb:UpdateItem",
#           "dynamodb:GetItem",
#           "dynamodb:Query",
#           "dynamodb:GetRecords",
#           "dynamodb:GetShardIterator",
#           "dynamodb:DescribeStream",
#           "dynamodb:ListStreams",
#           "dynamodb:ListTables"
#         ]
#         Resource = [
#           aws_dynamodb_table.sensor_data.arn,
#           "${aws_dynamodb_table.sensor_data.arn}/stream/*"
#         ]
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "s3:PutObject",
#           "s3:GetObject",
#           "s3:ListBucket"
#         ]
#         Resource = [
#           aws_s3_bucket.sensor_archive.arn,
#           "${aws_s3_bucket.sensor_archive.arn}/*"
#         ]
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "logs:CreateLogGroup",
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ]
#         Resource = "arn:aws:logs:*:*:*"
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "sqs:SendMessage",
#           "sqs:ReceiveMessage",
#           "sqs:DeleteMessage",
#           "sqs:GetQueueAttributes"
#         ]
#         Resource = aws_sqs_queue.sensor_queue.arn
#       }
#     ]
#   })
# }
