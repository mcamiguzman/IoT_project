╷
│ Error: creating IAM Policy (iot-topic-rule-extra-dev): operation error IAM: CreatePolicy, https response error StatusCode: 403, RequestID: 8b3af396-c37b-48fa-8cd0-b6af6b094e14, api error AccessDenied: User: arn:aws:sts::654654585203:assumed-role/voclabs/user4170344=Mateo_Ram__rez_Gutierrez is not authorized to perform: iam:TagPolicy on resource: policy iot-topic-rule-extra-dev because no identity-based policy allows the iam:TagPolicy action
│
│   with aws_iam_policy.iot_topic_rule_extra[0],
│   on iot_core.tf line 157, in resource "aws_iam_policy" "iot_topic_rule_extra":
│  157: resource "aws_iam_policy" "iot_topic_rule_extra" {
│
╵
╷
│ Error: creating IoT Topic Rule (iot_rule_to_s3_dev): operation error IoT: CreateTopicRule, https response error StatusCode: 400, RequestID: 7ed2f50a-7bce-4bd7-9644-46c7d439ee09, InvalidRequestException: Errors encountered while validating query.
│ ERROR: The provided function year does not exist
│  * ERROR: The provided function month does not exist
│  * ERROR: The provided function day does not exist
│  * ERROR: The provided function hour does not exist
│  * ERROR: The provided function minute does not exist
│
│   with aws_iot_topic_rule.to_s3,
│   on iot_core.tf line 211, in resource "aws_iot_topic_rule" "to_s3":
│  211: resource "aws_iot_topic_rule" "to_s3" {
│
╵
╷
│ Error: creating Lambda Function (iot-process-s3-dev): operation error Lambda: CreateFunction, https response error StatusCode: 413, RequestID: 3f9bb9da-12c8-4ad5-93f7-023ebe13fefe, api error RequestEntityTooLargeException: Request must be smaller than 70167211 bytes for the CreateFunction operation
│
│   with aws_lambda_function.process_s3,
│   on lambda.tf line 26, in resource "aws_lambda_function" "process_s3":
│   26: resource "aws_lambda_function" "process_s3" {
│
╵