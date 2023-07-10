##################### SQS queue #################################


resource "aws_sqs_queue" "infinit" {
  name                       = var.sqs_queue_name
  visibility_timeout_seconds = 120
  message_retention_seconds   = 86400
  delay_seconds              = 2
}



resource "aws_sqs_queue_policy" "infinit" {
  queue_url = "https://sqs.${var.aws_region}.amazonaws.com/${var.aws_account}/${var.sqs_queue_name}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "__default_policy_ID",
  "Statement": [
    {
      "Sid": "__owner_statement",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${var.aws_account}:root"
      },
      "Action": "SQS:*",
      "Resource": "arn:aws:sqs:${var.aws_region}:${var.aws_account}:${var.sqs_queue_name}"
    },
    {
      "Sid": "AWSEvents_spot-interruption",
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sqs:SendMessage",
      "Resource": "arn:aws:sqs:${var.aws_region}:${var.aws_account}:${var.sqs_queue_name}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "arn:aws:events:${var.aws_region}:${var.aws_account}:rule/karpenter-${var.cluster_name}-*"
        }
      }
    }
  ]
}
POLICY
}



##################### eventbridge rules #####################


resource "aws_cloudwatch_event_rule" "eventbridge-3" {
  name        = "karpenter-${var.cluster_name}-spot-interruption"
  description = "send spot interuption warning to karpenter-${var.cluster_name}-sqs"

  event_pattern = <<EOF
{
  "source": [
    "aws.ec2"
  ],  
  "detail-type": [
    "EC2 Spot Instance Interruption Warning"
  ]
}
EOF
}


resource "aws_cloudwatch_event_rule" "eventbridge-1" {
  name        = "karpenter-${var.cluster_name}-state-change"
  description = "send Instance State-change Notifications to karpenter-${var.cluster_name}-sqs"

  event_pattern = <<EOF
{
  "source": [
    "aws.ec2"
  ],  
  "detail-type": [
    "EC2 Instance State-change Notification"
  ]
}
EOF
}

resource "aws_cloudwatch_event_rule" "eventbridge-2" {
  name        = "karpenter-${var.cluster_name}-instance-rebbalance"
  description = "send Instance Rebalance Recommendation to karpenter-${var.cluster_name}-sqs"

  event_pattern = <<EOF
{
  "source": [
    "aws.ec2"
  ],  
  "detail-type": [
    "EC2 Instance Rebalance Recommendation"
  ]
}
EOF
}

resource "aws_cloudwatch_event_target" "eventbridge-1" {
  rule      = aws_cloudwatch_event_rule.eventbridge-1.name
  arn       = aws_sqs_queue.infinit.arn
}

resource "aws_cloudwatch_event_target" "eventbridge-2" {
  rule      = aws_cloudwatch_event_rule.eventbridge-2.name
  arn       = aws_sqs_queue.infinit.arn
}

resource "aws_cloudwatch_event_target" "eventbridge-3" {
  rule      = aws_cloudwatch_event_rule.eventbridge-3.name
  arn       = aws_sqs_queue.infinit.arn
}
