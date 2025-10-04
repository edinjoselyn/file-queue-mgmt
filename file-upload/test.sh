#!/bin/bash
set -e

CLUSTER_NAME="fargate-demo-cluster"
SERVICE_NAME="fargate-java21-service"
AWS_REGION="us-west-1"
API_ENDPOINT="/hello"  # change to your REST endpoint

# 1️⃣ Get the first running task
TASK_ID=$(aws ecs list-tasks \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --region $AWS_REGION \
  --query "taskArns[0]" \
  --output text)

if [ -z "$TASK_ID" ]; then
  echo "No running tasks found for service $SERVICE_NAME"
  exit 1
fi

# 2️⃣ Get the public IP of the task
ENI_ID=$(aws ecs describe-tasks \
         --cluster $CLUSTER_NAME \
         --tasks $TASK_ID \
         --region $AWS_REGION \
         --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
         --output text)

PUBLIC_IP=$(aws ec2 describe-network-interfaces \
              --network-interface-ids $ENI_ID \
              --region us-west-1 \
              --query "NetworkInterfaces[0].Association.PublicIp")

if [ -z "$PUBLIC_IP" ]; then
  echo "No public IP found. Make sure your task has assignPublicIp=ENABLED and is in a public subnet."
  exit 1
fi

echo "Public IP of Fargate task: $PUBLIC_IP"

# 3️⃣ Curl the API
echo "Testing API endpoint..."
# Capture output
RESPONSE=$(curl -s http://$PUBLIC_IP:8080$API_ENDPOINT)
# Print it
echo "Response:" $RESPONSE

#aws ec2 describe-security-groups \
#  --group-ids sg-5259f92d \
#  --region us-west-1 \
#  --query "SecurityGroups[].IpPermissions"

#aws ecs list-tasks \
#  --cluster fargate-demo-cluster \
#  --service-name fargate-java21-service \
#  --region us-west-1 \
#  --query "taskArns[0]"

#aws ecs describe-tasks \
#  --cluster fargate-demo-cluster \
#  --tasks "arn:aws:ecs:us-west-1:523919781340:task/fargate-demo-cluster/bd573f44060b414392fae0e1a77a18f1" \
#  --region us-west-1 \
#  --query "tasks[0].attachments[0].details"

  #--query "tasks[0].platformVersion"
  #--query "tasks[0].attachments[0].details[?name=='subnetId'].value" \
  #--query "tasks[0].attachments[0].details"
  #--query "tasks[0].attachments[0].details[?name=='publicIPv4Address'].value" \

#
#aws ec2 describe-subnets \
#  --region us-west-1 \
#  --filters Name=vpc-id,Values=vpc-15160372 \
#  --query "Subnets[?MapPublicIpOnLaunch=='true'].SubnetId" \
#  --output text

#aws ec2 describe-network-interfaces \
#  --network-interface-ids eni-087e6a3a592dfc48e \
#  --region us-west-1 \
#  --query "NetworkInterfaces[0].Association.PublicIp"