#!/bin/bash
set -e

# ===== CONFIG =====
AWS_REGION="us-west-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
REPO_NAME="fargate-java21-demo"
IMAGE_TAG="latest"
CLUSTER_NAME="fargate-demo-cluster"
SERVICE_NAME="fargate-java21-service"
TASK_FAMILY="fargate-java21-task"
LOG_GROUP="$REPO_NAME"   # MUST match actual CloudWatch log group name
CONTAINER_PORT=8080
VPC_ID="vpc-15160372"
SECURITY_GROUP="sg-5259f92d"
AVAILABILITY_ZONE="us-west-1a"
#SUBNET_ID=$(aws ec2 describe-subnets --region $AWS_REGION --query "Subnets[0].SubnetId" --output text)
#SG_ID=$(aws ec2 describe-security-groups --region $AWS_REGION --query "SecurityGroups[0].GroupId" --output text)

# --- 1️⃣ Find the IGW attached to the VPC ---
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters Name=attachment.vpc-id,Values=$VPC_ID \
  --region $AWS_REGION \
  --query "InternetGateways[0].InternetGatewayId" \
  --output text --no-cli-pager)

if [ -z "$IGW_ID" ] || [ "$IGW_ID" == "None" ]; then
  echo "No Internet Gateway found for VPC $VPC_ID. Please attach one first."
  exit 1
fi
echo "Using IGW: $IGW_ID"

# --- 2️⃣ Find a route table associated with the VPC ---
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values=$VPC_ID \
  --region $AWS_REGION \
  --query "RouteTables[0].RouteTableId" \
  --output text --no-cli-pager)

echo "Using route table: $ROUTE_TABLE_ID"

# --- 3️⃣ Pick a free CIDR block inside the VPC ---
# List existing subnets
EXISTING_CIDRS=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=$VPC_ID \
  --region $AWS_REGION \
  --query "Subnets[*].CidrBlock" \
  --output text --no-cli-pager)

# Example: VPC CIDR 172.31.0.0/20, find next /24 not used
# For simplicity, using 172.31.32.0/20
NEW_SUBNET_CIDR="172.31.32.0/20"

for cidr in $EXISTING_CIDRS; do
  if [ "$cidr" == "$NEW_SUBNET_CIDR" ]; then
    echo "CIDR $NEW_SUBNET_CIDR already exists. Pick another free block."
    exit 1
  fi
done

# --- 4️⃣ Create the public subnet ---
NEW_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $NEW_SUBNET_CIDR \
  --availability-zone $AVAILABILITY_ZONE \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=public-subnet}]" \
  --region $AWS_REGION \
  --query "Subnet.SubnetId" \
  --output text --no-cli-pager)

echo "Created public subnet: $NEW_SUBNET_ID"

# --- 5️⃣ Enable auto-assign public IP ---
aws ec2 modify-subnet-attribute \
  --subnet-id $NEW_SUBNET_ID \
  --map-public-ip-on-launch \
  --region $AWS_REGION

echo "Enabled auto-assign public IP"

# --- 6️⃣ Associate subnet with route table ---
aws ec2 associate-route-table \
  --subnet-id $NEW_SUBNET_ID \
  --route-table-id $ROUTE_TABLE_ID \
  --region $AWS_REGION

echo "Associated subnet with route table"

# --- 7️⃣ Add route to Internet Gateway if not exists ---
aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $AWS_REGION || echo "Route may already exist"

echo "Route to IGW ensured"