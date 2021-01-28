locals {
  domain = {
    production = {
      domain_name               = "${var.service_name}.${var.domain_name}"
      subject_alternative_names = "${var.service_name}.${var.domain_name}"
    }
    staging = {
      domain_name               = "${terraform.workspace}.${var.service_name}.${var.domain_name}"
      subject_alternative_names = "*.${var.service_name}.${var.domain_name}"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "self" { }

########
# VPC
resource "aws_vpc" "base" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_a" {
  vpc_id = aws_vpc.base.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "ap-northeast-1a"
  tags = { name = "${var.service_name}-${terraform.workspace}-ecs-private-subnet-a" }
}

resource "aws_subnet" "public_c" {
  vpc_id = aws_vpc.base.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-northeast-1c"
  tags = { name = "${var.service_name}-${terraform.workspace}-ecs-private-subnet-c" }
}

resource "aws_subnet" "ecs_private_a" {
  vpc_id = aws_vpc.base.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"
  tags = { name = "${var.service_name}-${terraform.workspace}-ecs-private-subnet-a" }
}
resource "aws_subnet" "ecs_private_c" {
  vpc_id = aws_vpc.base.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "ap-northeast-1c"
  tags = { name = "${var.service_name}-${terraform.workspace}-ecs-private-subnet-c" }
}

resource "aws_subnet" "rds_private_a" {
  vpc_id = aws_vpc.base.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "ap-northeast-1a"
  tags = { name = "${var.service_name}-${terraform.workspace}-rds-private-subnet-a" }
}
resource "aws_subnet" "rds_private_c" {
  vpc_id = aws_vpc.base.id
  cidr_block = "10.0.5.0/24"
  availability_zone = "ap-northeast-1c"
  tags = { name = "${var.service_name}-${terraform.workspace}-rds-private-subnet-c" }
}

resource "aws_eip" "public_a" {}
resource "aws_eip" "public_c" {}

resource "aws_nat_gateway" "public_a" {
  allocation_id = aws_eip.public_a.id
  subnet_id = aws_subnet.public_a.id
}

resource "aws_nat_gateway" "public_c" {
  allocation_id = aws_eip.public_c.id
  subnet_id = aws_subnet.public_c.id
}

resource "aws_egress_only_internet_gateway" "egress" {
  vpc_id = aws_vpc.base.id
  tags = {
    Name      = "${var.service_name}-${terraform.workspace}-egress"
    Terraform = "true"
  }
}

resource "aws_route_table" "public_a" {
  vpc_id = aws_vpc.base.id
  tags = {
    Name      = "${var.service_name}-${terraform.workspace}-public-a"
    Terraform = "true"
  }
}

resource "aws_route_table" "public_c" {
  vpc_id = aws_vpc.base.id
  tags = {
    Name      = "${var.service_name}-${terraform.workspace}-public-c"
    Terraform = "true"
  }
}

resource "aws_route_table" "ecs_a" {
  vpc_id = aws_vpc.base.id
  tags = {
    Name      = "${var.service_name}-${terraform.workspace}-ecs-a"
    Terraform = "true"
  }
}

resource "aws_route_table" "ecs_c" {
  vpc_id = aws_vpc.base.id
  tags = {
    Name      = "${var.service_name}-${terraform.workspace}-ecs-c"
    Terraform = "true"
  }
}

resource "aws_route_table_association" "ecs_a" {
  subnet_id      = aws_subnet.ecs_private_a.id
  route_table_id = aws_route_table.ecs_a.id
}

resource "aws_route_table_association" "ecs_c" {
  subnet_id      = aws_subnet.ecs_private_c.id
  route_table_id = aws_route_table.ecs_c.id
}

resource "aws_route" "public_a_igw" {
  route_table_id              = aws_route_table.public_a.id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.egress.id
}

resource "aws_route" "public_c_igw" {
  route_table_id              = aws_route_table.public_c.id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.egress.id
}

resource "aws_route" "ecs_a" {
  route_table_id              = aws_route_table.ecs_a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id      = aws_nat_gateway.public_a.id
}

resource "aws_route" "ecs_c" {
  route_table_id              = aws_route_table.ecs_c.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id      = aws_nat_gateway.public_c.id
}

##########
# Route53
resource "aws_route53_zone" "primary" {
  name = var.domain_name
}

resource "aws_route53_record" "sub" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = local.domain[terraform.workspace]["domain_name"]
  type    = "A"
  alias {
      name                   = aws_cloudfront_distribution.web_front.domain_name
      zone_id                = aws_cloudfront_distribution.web_front.hosted_zone_id
      evaluate_target_health = false
    }
}

resource "aws_acm_certificate" "cloudfront" {
  domain_name               = local.domain[terraform.workspace]["subject_alternative_names"]
  validation_method         = "DNS"
  # https://aws.amazon.com/jp/premiumsupport/knowledge-center/custom-ssl-certificate-cloudfront/
  provider                  = "aws.virginia"

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
  lifecycle {
    # prevent_destroy = true
  }
  tags = {
    Terraform = "true",
  }
}

resource "aws_acm_certificate_validation" "cloudfront" {
  certificate_arn = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
  provider                  = "aws.virginia"
}

################
# ALB
resource "aws_security_group" "alb" {
  name = "${var.service_name}-${terraform.workspace}-alb"
  description = "sg-${var.service_name}-${terraform.workspace}-lb"
  egress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
      ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
  ]
  ingress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
      ]
      description = ""
      from_port   = 443
      ipv6_cidr_blocks = [
        "::/0",
      ]
      prefix_list_ids = []
      protocol        = "tcp"
      security_groups = []
      self            = false
      to_port         = 443
    }
  ]
  tags = {
    Terraform = "true"
  }
  vpc_id = aws_vpc.base.id
}

resource "aws_lb" "web_api" {
  name     = "${var.service_name}-${terraform.workspace}-alb"

  enable_deletion_protection = false
  enable_http2               = true
  idle_timeout               = 60
  internal                   = false
  ip_address_type            = "ipv4"
  load_balancer_type         = "application"
  security_groups = [
    aws_security_group.alb.id
  ]
  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_c.id,
  ]
  tags = {
    Terraform = "true",
  }

  access_logs {
    bucket  = aws_s3_bucket.log_bucket.bucket
    prefix  = ""
    enabled = true
  }

  timeouts {}
}

resource "aws_security_group_rule" "alb_vpc" {
  security_group_id         = aws_security_group.alb.id
  source_security_group_id  = aws_vpc.base.default_security_group_id

  type = "ingress"

  from_port = 0
  to_port   = 65535
  protocol  = "tcp"
}

resource "aws_acm_certificate" "alb" {
  domain_name               = local.domain[terraform.workspace]["subject_alternative_names"]
  validation_method         = "DNS"

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
  tags = {
    Terraform = "true",
  }
}

resource "aws_route53_record" "alb_cert_validation" {
  zone_id = data.aws_route53_zone.primary.zone_id
  for_each = {
    for dvo in aws_acm_certificate.alb.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  type       = each.value.type
  name       = each.value.name
  records    = [each.value.record]
  ttl        = 60
}

resource "aws_acm_certificate_validation" "alb" {
  certificate_arn = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for record in aws_route53_record.alb_cert_validation : record.fqdn]
}

resource "aws_lb_target_group" "api" {
  deregistration_delay = 30
  name                 = "${var.service_name}-${terraform.workspace}-alb-tg"
  port                 = 80
  protocol             = "HTTP"
  slow_start           = 0
  tags                 = {}
  target_type          = "instance"
  vpc_id               = aws_vpc.base.id

  health_check {
    enabled             = true
    healthy_threshold   = 5
    interval            = 30
    matcher             = "200"
    path                = "/api/v1/health_check"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  stickiness {
    cookie_duration = 86400
    enabled         = false
    type            = "lb_cookie"
  }
}

resource "aws_lb_listener" "api" {
  certificate_arn   = aws_acm_certificate.alb.arn
  load_balancer_arn = aws_lb.web_api.arn

  port       = 443
  protocol   = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-2016-08"

  default_action {
    order            = 1
    target_group_arn = aws_lb_target_group.api.arn
    type             = "forward"
  }
  depends_on = [aws_acm_certificate_validation.alb]

  timeouts {}
}

resource "aws_security_group" "ecs_cluster" {
  name = "${var.service_name}-${terraform.workspace}-ecs-cluster"
  description = "sg-${var.service_name}-${terraform.workspace}-ecs-cluster"
  egress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
      ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
  ]
  tags = {
    Terraform = "true"
  }
  vpc_id = aws_vpc.base.id
}

resource "aws_security_group_rule" "alb_to_ecs_http" {
  security_group_id         = aws_security_group.ecs_cluster.id
  source_security_group_id  = aws_security_group.alb.id

  type = "ingress"

  # Dynamic port mapping https://aws.amazon.com/jp/premiumsupport/knowledge-center/dynamic-port-mapping-ecs/
  from_port = 32768
  to_port   = 65535
  protocol  = "tcp"
}

resource "aws_security_group_rule" "default_to_ecs_ssh" {
  security_group_id         = aws_security_group.ecs-cluster.id
  source_security_group_id  = data.aws_security_group.vpc_default.id

  type = "ingress"

  from_port = 22
  to_port   = 22
  protocol  = "tcp"
}

output "ALB_DNS_name" {
  value = aws_lb.web_api.dns_name
}
