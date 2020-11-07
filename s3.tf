resource "aws_s3_bucket" "static_file_host" {
  bucket           = "${terraform.workspace}.${var.service_name}.${var.domain_name}"
  acl              = "private"

  versioning {
    enabled    = false
    mfa_delete = false
  }

  website {
    index_document = "index.html"
  }

  lifecycle {
    # prevent_destroy = true
  }
  tags             = { "Terraform" = "true" }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket           = "log.${terraform.workspace}.${var.service_name}.${var.domain_name}"
  request_payer    = "BucketOwner"
  acl              = "private"
  policy           = data.aws_iam_policy_document.log_bucket.json
  lifecycle {
    # prevent_destroy = true
  }
  tags             = { "Terraform" = "true" }
}

data "aws_iam_policy_document" "log_bucket" {
  statement {
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = ["arn:aws:iam::468071515200:root"]
    }
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "arn:aws:s3:::log.${terraform.workspace}.${var.service_name}.${var.domain_name}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "static_file_host" {
  bucket = aws_s3_bucket.static_file_host.id
  policy = data.aws_iam_policy_document.static_file_host.json
}

data "aws_iam_policy_document" "static_file_host" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.static_file_host.bucket}/*"
    ]
    principals {
      type = "AWS"
      identifiers = ["arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${aws_cloudfront_origin_access_identity.static_file_host.id}"]
    }
  }
}

resource "aws_s3_bucket_policy" "allow_for_github_action_iam" {
  bucket = aws_s3_bucket.static_file_host.id
  policy = data.aws_iam_policy_document.allow_for_github_action_iam.json
}

data "aws_iam_policy_document" "allow_for_github_action_iam" {
  statement {
    effect = "Allow"
    actions = [
      "s3:Put*"
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.static_file_host.bucket}/*",
      "arn:aws:s3:::${aws_s3_bucket.static_file_host.bucket}"
    ]
    principals {
      type = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.self.account_id}:user/${var.github_action_iam_user}"]
    }
  }
}

output "static_file_host_bucket_name" {
  value = aws_s3_bucket.static_file_host.id
}
