#################
# KMS
resource "aws_kms_key" "master" {
  description         = "Default master key"
  enable_key_rotation = true
  is_enabled          = true
  key_usage           = "ENCRYPT_DECRYPT"
  policy = jsonencode(
    {
      Statement = [
        {
          Action = [
            "kms:*",
          ]
          Condition = {
            StringEquals = {
              "kms:CallerAccount" = data.aws_caller_identity.self.account_id
            }
          }
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::${data.aws_caller_identity.self.account_id}:root"
          }
          Resource = "*"
          Sid      = "Enable IAM Role Permissions"
        }
      ]
      Version = "2012-10-17"
    }
  )
  tags = { "Terraform" = "true" }
}

resource "aws_kms_alias" "master" {
  name          = "alias/${var.service_name}-${terraform.workspace}-master"
  target_key_id = aws_kms_key.master.key_id
}

#################
# SSM
resource "aws_ssm_parameter" "rails_master_key" {
  name  = "/${var.service_name}/${terraform.workspace}/app/rails-master-key"
  value = var.rails_master_key
  type = "SecureString"
  key_id = aws_kms_key.master.key_id
}

resource "aws_ssm_parameter" "rds_postgres_password" {
  name  = "/${var.service_name}/${terraform.workspace}/rds/pg-password"
  value = random_string.rds_postgres_password.result
  type = "SecureString"
  key_id = aws_kms_key.master.key_id
}

resource "aws_ssm_parameter" "rds_postgres_user" {
  name  = "/${var.service_name}/${terraform.workspace}/rds/pg-user"
  value = "postgres"
  type = "String"
}

resource "aws_ssm_parameter" "rds_postgres_host" {
  name  = "/${var.service_name}/${terraform.workspace}/rds/pg-host"
  value = local.rds_cluster_writer_instance_endpoint[0]
  type = "String"
}

resource "aws_ssm_parameter" "rds_postgres_database" {
  name  = "/${var.service_name}/${terraform.workspace}/rds/pg-database"
  value = var.service_name
  type = "String"
}
