variable "service_name" {}

variable "domain_name" {}

variable "ecs_optimized_ami" {
  default = "ami-06ee72c3360fd7fad"
}

variable "ec2_instance_type" {
  # needs to be for ECS instance
  default = "c5a.large"
}

variable "rds_instance_class" {
  default = "db.t3.medium"
}

variable "instance_key_name" {}

variable "container_port" {
  # In case we develop ruby on rails application in backend
  default = 3000
}

# In case we develop ruby on rails application in backend
variable "rails_master_key" {}

# sqs endpoint
variable "resource_sqs" {}

# In case restrict access from out of network
variable "ipset_name" {}

variable "custom_header_value_via_cloudfront" {}

variable "developers" {}

variable "desired_container_count" {
  default = "2"
}

variable "github_action_iam_user" {}
