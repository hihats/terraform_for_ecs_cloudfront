data "aws_iam_policy_document" "ec2-assume-role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs-tasks-assume-role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com", "ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "sqs-send-message" {
  name       = "${var.service_name}-${terraform.workspace}-sqs-send_message-policy"
  policy     = data.aws_iam_policy_document.sqs-send-message.json
}

data "aws_iam_policy_document" "sqs-send-message" {
  statement {
    actions = [
      "sqs:SendMessage"
    ]
    effect    = "Allow"
    resources = ["arn:aws:sqs:${var.resource_sqs}"]
  }
}

resource "aws_iam_policy" "kms_key_decrypt" {
  name       = "kms-key-decrypt-policy"
  policy     = data.aws_iam_policy_document.kms_key_decrypt.json
}

data "aws_iam_policy_document" "kms_key_decrypt" {
  statement {
    actions = [
      "kms:Decrypt"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
}

resource "aws_iam_policy" "s3_getputdelete" {
  name       = "${var.service_name}-${terraform.workspace}-ecs-task-policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}
