#!/bin/bash
echo "ECS_CLUSTER=${ecs_cluster_name}" >> /etc/ecs/ecs.config
echo "ECS_ENABLE_TASK_IAM_ROLE=true" >> /etc/ecs/ecs.config
yum update && yum install -y aws-cfn-bootstrap
/opt/aws/bin/cfn-init -v --region ${aws_region} --stack ${stack} --resource ClusterEC2LaunchConfiguration
