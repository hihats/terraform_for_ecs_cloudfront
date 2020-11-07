locals {
  autoscaling = {
    production = {
      ami = var.ecs_optimized_ami
      instance_type   = var.ec2_instance_type
      max_cluster_size  = 3
      desired_capacity = 1
    }
    staging = {
      ami = var.ecs_optimized_ami
      instance_type   = var.ec2_instance_type
      max_cluster_size  = 2
      desired_capacity = 1
    }
  }
}

################
# ECS cluster
resource "aws_ecs_cluster" "app" {
  name = "${var.service_name}-${terraform.workspace}-ecs-cluster"
  capacity_providers = [aws_ecs_capacity_provider.app.name]
}

################
# AutoScaling
resource "aws_placement_group" "web" {
  name     = "${var.service_name}-${terraform.workspace}-pg"
  strategy = "cluster"
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
}

module "key_pair" {
  source = "terraform-aws-modules/key-pair/aws"

  key_name   = "${var.service_name}-${terraform.workspace}_key_pair"
  public_key = tls_private_key.this.public_key_openssh
}

resource "aws_iam_role" "app_container_instance" {
  name = "${var.service_name}-${terraform.workspace}-app-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2-assume-role.json
}

resource "aws_iam_instance_profile" "app_container_instance" {
  name = "${var.service_name}-${terraform.workspace}-ecs-instprofile"
  role = aws_iam_role.app_container_instance.name
}

resource "aws_iam_role_policy_attachment" "app_container_instance" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
  role       = aws_iam_role.app_container_instance.name
}

data "template_file" "cloud_config" {
  template = file("./asg/userdata.sh")

  vars = {
    aws_region         = data.aws_region.current.name
    ecs_cluster_name   = "${var.service_name}-${terraform.workspace}-ecs-cluster"
    stack              = var.service_name
  }
}

data "template_file" "add_user" {
  for_each = toset(var.developers)
  template = file("./asg/add_user.sh")

  vars = {
    username           = each.key
    public_key         = file("./asg/ssh/${each.key}.pkey")
  }
}

resource "aws_launch_configuration" "api" {
  name                        = "${var.service_name}-${terraform.workspace}-lc"
  image_id                    = local.autoscaling[terraform.workspace]["ami"]
  instance_type               = local.autoscaling[terraform.workspace]["instance_type"]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  user_data                   = "${data.template_file.cloud_config.rendered}${data.template_file.add_user[var.developers[0]].rendered}${data.template_file.add_user[var.developers[1]].rendered}"

  associate_public_ip_address = true
  key_name                    = var.instance_key_name
  security_groups             = [aws_security_group.ecs-cluster.id]

  # destroyすると影響反映が結構大きいので要再検討
  lifecycle {
    create_before_destroy = true
  }

}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.service_name}-${terraform.workspace}-asg"
  max_size                  = local.autoscaling[terraform.workspace]["max_cluster_size"]
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  target_group_arns         = [aws_lb_target_group.api.arn]
  desired_capacity          = local.autoscaling[terraform.workspace]["desired_capacity"]
  force_delete              = true
  placement_group           = aws_placement_group.web.id
  launch_configuration      = aws_launch_configuration.api.name
  vpc_zone_identifier       = [
    aws_subnet.ecs-private-a.id,
    aws_subnet.ecs-private-c.id
  ]

  timeouts {
    delete = "5m"
  }

  tag {
    key                 = "Name"
    value               = "${var.service_name}-${terraform.workspace}"
    propagate_at_launch = true
  }
}

resource "aws_ecs_capacity_provider" "app" {
  # Currentry, we cannot delete capacity provider. If you exec 'terraform destroy', you can delete resouce only on tfstate.
  name = "${var.service_name}-${terraform.workspace}_ecp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.app.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 100
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}
