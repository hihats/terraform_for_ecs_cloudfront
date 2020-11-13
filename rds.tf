locals {
  rds = {
    production = {
      instance_count  = 2
      instance_class  = var.rds_instance_class
    }
    staging = {
      instance_count  = 1
      instance_class  = "db.t3.medium"
    }
  }
}

resource "aws_rds_cluster" "app" {
  availability_zones = [
    "ap-northeast-1a",
    "ap-northeast-1c",
    "ap-northeast-1d"
  ]
  backtrack_window                    = 0
  backup_retention_period             = 3
  cluster_identifier                  = "${var.service_name}-${terraform.workspace}"
  copy_tags_to_snapshot               = true
  # database_name                       = ''  Delegates to ECS task
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.aurora_postgres.name
  db_subnet_group_name                = aws_db_subnet_group.app.name
  deletion_protection                 = false
  enabled_cloudwatch_logs_exports     = []
  engine                              = "aurora-postgresql"
  engine_mode                         = "provisioned"
  engine_version                      = "11.6"
  iam_database_authentication_enabled = false
  # iam_roles = [
  #   "arn:aws:iam::468071515200:role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS",
  # ]
  kms_key_id                   = "arn:aws:kms:ap-northeast-1:468071515200:key/ed3ec799-569e-49ce-801f-f3fc440ddd46"
  # kms_key_id                   = aws_kms_key.aws_rds.arn
  master_username              = "root"
  master_password              = random_string.rds_root_password.result
  port                         = 5432
  preferred_backup_window      = "18:22-18:52"
  preferred_maintenance_window = "fri:14:27-fri:14:57"
  skip_final_snapshot          = true
  storage_encrypted            = true
  vpc_security_group_ids = [
    aws_security_group.rds.id,
  ]
  lifecycle {
    # prevent_destroy = true
  }

  tags = {
    Terraform = "true"
  }

  timeouts {}
}

resource "aws_rds_cluster_instance" "app" {
  count              = local.rds[terraform.workspace]["instance_count"]
  identifier         = "${var.service_name}-${terraform.workspace}-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.app.cluster_identifier
  depends_on         = [aws_rds_cluster.app]
  instance_class     = local.rds[terraform.workspace]["instance_class"]

  engine             = aws_rds_cluster.app.engine
  engine_version     = aws_rds_cluster.app.engine_version
  # Don't specify in case of Multi AZ
  # availability_zone  = "ap-northeast-1a"

  db_parameter_group_name = aws_db_parameter_group.aurora_postgres.name

  lifecycle {
    # prevent_destroy = true
  }

  tags = {
    Terraform = "true"
  }
  timeouts {}
}

resource "random_string" "rds_root_password" {
  length  = 16
  special = false
}

resource "random_string" "rds_postgres_password" {
  length  = 16
  special = false
}

################
# Paramter Group
resource "aws_rds_cluster_parameter_group" "aurora_postgres" {
  name        = "${var.service_name}-${terraform.workspace}-aurora-postgres-cluster"
  family      = "aurora-postgresql11"
  description = "aurora postgresql11 RDS cluster parameter group"

  # parameter {
  #   name = "server_encoding"
  #   value = "utf8mb4"
  # }
  parameter {
    name = "timezone"
    value = "UTC+9"
  }
  # parameter {
  #   name = "log_timezone"
  #   value = "UTC+9"
  # }
}

resource "aws_db_parameter_group" "aurora_postgres" {
  family      = "aurora-postgresql11"
  name        = "${var.service_name}-${terraform.workspace}-aurora-postgres-db-instance"
  description = "${var.service_name}-${terraform.workspace} aurora postgresql11 db instance parameter group"

  parameter {
    name = "log_min_duration_statement"
    value = 1000
  }
  parameter {
    name  = "rds.log_retention_period"
    value = 10080
  }
  parameter {
    name = "rds.force_admin_logging_level"
    value = "info"
  }

  tags = {
    Terraform = "true"
  }
}

##########################
# Subnet & Security Group
resource "aws_db_subnet_group" "app" {
  name        = "${var.service_name}-${terraform.workspace}-db-subnet-group"
  subnet_ids = [
    aws_subnet.rds_private_a.id,
    aws_subnet.rds_private_c.id
  ]
  tags = {
    Terraform = "true"
  }
}

resource "aws_security_group" "rds" {
  description = "sg-${var.service_name}-${terraform.workspace}-rds"
  name = "${var.service_name}-${terraform.workspace}-rds-sg"
  tags = {
    Terraform = "true"
  }
  vpc_id = aws_vpc.base.id
}

resource "aws_security_group_rule" "ecs_to_rds" {
  security_group_id = aws_security_group.rds.id
  source_security_group_id  = aws_security_group.ecs_cluster.id

  type = "ingress"

  from_port = 5432
  to_port   = 5432
  protocol  = "tcp"
}

resource "aws_security_group_rule" "default_rds" {
  security_group_id = aws_security_group.rds.id
  source_security_group_id  = aws_vpc.base.default_security_group_id

  type = "ingress"

  from_port = 5432
  to_port   = 5432
  protocol  = "tcp"
}

# To regiter database hostname for application container's variable
locals {
  rds_cluster_writer_instance_endpoint = [
    for instance in aws_rds_cluster_instance.app: instance.endpoint if instance.writer
  ]
}

output "rds_cluster_writer_instance_endpoint" {
  value = local.rds_cluster_writer_instance_endpoint
}

output "rds_database_root_password" {
  value = aws_rds_cluster.app.master_password
}

output "rds_database_postgres_password" {
  value = random_string.rds_postgres_password.result
}
