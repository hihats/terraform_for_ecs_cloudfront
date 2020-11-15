########################
# IAM Role for ECS Task
resource "aws_iam_role" "ecs_task_execution" {
  name         = "${var.service_name}-${terraform.workspace}-ecs-task-execution-role"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          Action : "sts:AssumeRole",
          Effect : "Allow",
          Principal : {
            "Service" : "ecs-tasks.amazonaws.com"
          }
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_ssm_read" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_kms_key_decrypt" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.kms_key_decrypt.arn
}

resource "aws_iam_role" "ecs_task_role" {
  name         = "${var.service_name}-${terraform.workspace}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs-tasks-assume-role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_s3_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.s3_getputdelete.arn
}

resource "aws_iam_role_policy_attachment" "ecs_task_sqs_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.sqs-send-message.arn
}

####################
# ECS Service & Task
resource "aws_ecs_service" "app" {
  name            = "${var.service_name}-${terraform.workspace}-service"
  task_definition = aws_ecs_task_definition.app.arn
  cluster         = aws_ecs_cluster.app.arn

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.app.name
    weight = 1
    base = 1
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "${var.service_name}-api-task"
    container_port   = var.container_port
  }

  desired_count                      = var.desired_container_count
  deployment_maximum_percent         = (var.desired_container_count + 1) / var.desired_container_count * 100
  deployment_minimum_healthy_percent = 100 / var.desired_container_count
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  lifecycle {
    ignore_changes = [
      task_definition, capacity_provider_strategy
    ]
  }
}

resource "aws_ecs_task_definition" "app" {
  container_definitions    = data.template_file.run-app-task_definition.rendered
  family                   = "${var.service_name}-${terraform.workspace}-app"
  cpu                      = "512"
  memory                   = "512"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  depends_on = [aws_rds_cluster_instance.app]
}

data "template_file" "run-app-task_definition" {
  template = file("./ecs_task_definitions/app.json")

  vars = {
    region = data.aws_region.current.name
    log_group   = aws_cloudwatch_log_group.ecs-task.name
    stream_prefix = var.service_name
    database_name = var.service_name
    database_password = random_string.rds_postgres_password.result
    rds_instance_endpoint = local.rds_cluster_writer_instance_endpoint[0]
    rails_master_key = aws_ssm_parameter.rails_master_key.arn
    env = terraform.workspace
  }
}

resource "aws_ecs_task_definition" "app-db-create" {
  container_definitions    = data.template_file.db_create_task_definition.rendered
  family                   = "${var.service_name}-${terraform.workspace}-db-create"
  cpu                      = 1024
  memory                   = 2048
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  depends_on = [aws_rds_cluster_instance.app]
}

data "template_file" "db_create_task_definition" {
  template = file("./ecs_task_definitions/db.json")

  vars = {
    region = data.aws_region.current.name
    log_group   = aws_cloudwatch_log_group.ecs-task.name
    stream_prefix = var.service_name
    database_name = var.service_name
    database_password = random_string.rds_postgres_password.result
    rds_instance_endpoint = local.rds_cluster_writer_instance_endpoint[0]
    command = "create"
    rails_master_key = aws_ssm_parameter.rails_master_key.arn
    env = terraform.workspace
  }
}

resource "aws_ecs_task_definition" "app-db-migrate" {
  container_definitions    = data.template_file.db_migrate_task_definition.rendered
  family                   = "${var.service_name}-${terraform.workspace}-db-migrate"
  cpu                      = 1024
  memory                   = 2048
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  depends_on = [aws_rds_cluster_instance.app]
}

data "template_file" "db_migrate_task_definition" {
  template = file("./ecs_task_definitions/db.json")

  vars = {
    region = data.aws_region.current.name
    log_group   = aws_cloudwatch_log_group.ecs-task.name
    stream_prefix = var.service_name
    database_name = var.service_name
    database_password = random_string.rds_postgres_password.result
    rds_instance_endpoint = local.rds_cluster_writer_instance_endpoint[0]
    command = "migrate"
    rails_master_key = aws_ssm_parameter.rails_master_key.arn
    env = terraform.workspace
  }
}

resource "aws_ecs_task_definition" "app-db-seed" {
  container_definitions    = data.template_file.db_seed_task_definition.rendered
  family                   = "${var.service_name}-${terraform.workspace}-db-seed"
  cpu                      = 1024
  memory                   = 2048
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  depends_on = [aws_rds_cluster_instance.app]
}

data "template_file" "db_seed_task_definition" {
  template = file("./ecs_task_definitions/db.json")

  vars = {
    region = data.aws_region.current.name
    log_group   = aws_cloudwatch_log_group.ecs-task.name
    stream_prefix = var.service_name
    database_name = var.service_name
    database_password = random_string.rds_postgres_password.result
    rds_instance_endpoint = local.rds_cluster_writer_instance_endpoint[0]
    command = "seed_fu"
    rails_master_key = aws_ssm_parameter.rails_master_key.arn
    env = terraform.workspace
  }
}

resource "aws_cloudwatch_log_group" "ecs-task" {
  name = "${var.service_name}-${terraform.workspace}-log-group"

  tags = {
    Environment = terraform.workspace
    Application = var.service_name
  }
}

resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.app.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
