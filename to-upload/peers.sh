#!/bin/sh

AWS_CLI=/usr/local/bin/aws
source /etc/default/aws

# Read all instances from ECS cluster
ECS_INSTANCES_ARN=$($AWS_CLI ecs list-container-instances --region $REGION --cluster $ECS_CLUSTER --no-paginate | jq -r '.containerInstanceArns[]' | tr "\n" " ")
if [ ! -z "$ECS_INSTANCES_ARN" ]; then
  ECS_INSTANCES_IDS=$($AWS_CLI ecs describe-container-instances --region $REGION --cluster $ECS_CLUSTER --container-instances $ECS_INSTANCES_ARN | jq -r '.containerInstances[].ec2InstanceId' | tr "\n" " ")
else
  # Read running instances from auto scaling group if they aren't in ECS cluster yet
  ASG_NAME=$($AWS_CLI autoscaling describe-auto-scaling-instances --region $REGION --query "AutoScalingInstances[?InstanceId==\`$INSTANCE_ID\`].AutoScalingGroupName" --output text)
  ECS_INSTANCES_IDS=$($AWS_CLI ec2 describe-instances --region $REGION --filters 'Name=tag:aws:autoscaling:groupName,Values='$ASG_NAME 'Name=instance-state-name,Values=running' | jq -r '.Reservations[].Instances[].InstanceId' | tr "\n" " ")
fi
$AWS_CLI ec2 describe-instances --region $REGION --instance-ids ${ECS_INSTANCES_IDS:-$INSTANCE_ID} --filters 'Name=instance-state-name,Values=running' | jq -r '.Reservations[].Instances[].PrivateIpAddress'
