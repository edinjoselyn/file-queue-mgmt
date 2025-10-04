#!/bin/bash
set -e

# ===== CONFIG =====
AWS_REGION="us-west-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
REPO_NAME="fargate-java21-demo"
IMAGE_TAG="latest"
CLUSTER_NAME="fargate-demo-cluster"
SERVICE_NAME="fargate-java21-service"
TASK_DEF="fargate-java21-task"
LOG_GROUP="$REPO_NAME"   # MUST match actual CloudWatch log group name
CONTAINER_PORT=8080
SECURITY_GROUP="sg-5259f92d"
#SUBNET_ID=$(aws ec2 describe-subnets --region $AWS_REGION --query "Subnets[0].SubnetId" --output text)
#SG_ID=$(aws ec2 describe-security-groups --region $AWS_REGION --query "SecurityGroups[0].GroupId" --output text)
PUBLIC_SUBNET="subnet-0dd41718d7619cf29"

# ===== 1. Build JAR & Docker image =====
echo ">>> Building JAR..."
mvn clean package -DskipTests

echo ">>> Building Docker image for linux/amd64..."
docker buildx build \
  --platform linux/amd64 \
  -t $REPO_NAME:$IMAGE_TAG \
  .

# ===== 2. Ensure ECR repo exists =====
aws ecr describe-repositories --repository-names $REPO_NAME --region $AWS_REGION >/dev/null 2>&1 || \
aws ecr create-repository --repository-name $REPO_NAME --region $AWS_REGION

# ===== 3. Authenticate Docker & push image =====
docker tag $REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG

# ===== 4. Ensure CloudWatch log group exists =====
if ! aws logs describe-log-groups \
    --log-group-name-prefix $LOG_GROUP \
    --region $AWS_REGION \
    --query 'logGroups[*].logGroupName' --output text | grep -q "$LOG_GROUP"; then
    echo ">>> Creating CloudWatch log group: $LOG_GROUP"
    aws logs create-log-group --log-group-name $LOG_GROUP --region $AWS_REGION
fi

# ===== 5. Register ECS task definition =====
echo ">>> Registering ECS task definition..."
cat > taskdef.json <<EOF
{
  "family": "$TASK_DEF",
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskRole",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "containerDefinitions": [
    {
      "name": "$REPO_NAME",
      "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG",
      "essential": true,
      "portMappings": [
        {
          "containerPort": $CONTAINER_PORT,
          "protocol": "tcp"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "$LOG_GROUP",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF

aws ecs register-task-definition --cli-input-json file://taskdef.json --region $AWS_REGION --no-cli-pager

# ===== 6. Ensure ECS cluster exists =====
aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION \
  --query "clusters[0].status" --output text 2>/dev/null | grep -q "ACTIVE" || \
aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $AWS_REGION

# ===== 7. Create or update ECS service =====

# 1️⃣ Pick a public subnet automatically
#PUBLIC_SUBNET=$(aws ec2 describe-subnets \
#  --filters Name=vpc-id,Values=$VPC_ID \
#  --region $AWS_REGION \
#  --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId | [0]" \
#  --output text)
#
#if [ -z "$PUBLIC_SUBNET" ] || [ "$PUBLIC_SUBNET" == "None" ]; then
#  echo "Error: No public subnet found in VPC $VPC_ID"
#  exit 1
#fi

echo "Using public subnet: $PUBLIC_SUBNET"

# 2️⃣ Create or update ECS service
# --- 3️⃣ Check if ECS service exists ---
SERVICE_EXISTS=$(aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION \
  --query "services[0].status" \
  --output text --no-cli-pager)

LATEST_TASK=$(aws ecs describe-task-definition \
  --task-definition $TASK_DEF \
  --region $AWS_REGION \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

# --- 4️⃣ Create or update ECS service ---
if [ "$SERVICE_EXISTS" == "ACTIVE" ] || [ "$SERVICE_EXISTS" == "DRAINING" ]; then
    echo "Service exists — updating..."
    aws ecs update-service \
      --cluster $CLUSTER_NAME \
      --service $SERVICE_NAME \
      --task-definition $LATEST_TASK \
      --network-configuration "awsvpcConfiguration={subnets=[$PUBLIC_SUBNET],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}" \
      --platform-version LATEST \
      --force-new-deployment \
      --region $AWS_REGION \
      --no-cli-pager
else
    echo "Service does not exist — creating..."
    aws ecs create-service \
      --cluster $CLUSTER_NAME \
      --service-name $SERVICE_NAME \
      --task-definition $LATEST_TASK \
      --desired-count 1 \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[$PUBLIC_SUBNET],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}" \
      --platform-version LATEST \
      --region $AWS_REGION \
      --no-cli-pager
fi

# ===== 8. Wait for service to be running =====
echo ">>> Waiting for ECS service to reach RUNNING status..."
aws ecs wait services-stable \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION

echo "✅ Deployment complete! ECS service is running and logs will appear in CloudWatch group '$LOG_GROUP'."

#aws ecs update-service \
#      --cluster "fargate-demo-cluster" \
#      --service "fargate-java21-service" \
#      --task-definition "fargate-java21-task" \
#      --network-configuration "awsvpcConfiguration={subnets=[subnet-0dd41718d7619cf29],securityGroups=[sg-5259f92d],assignPublicIp=ENABLED}" \
#      --platform-version LATEST \
#      --force-new-deployment \
#      --region us-west-1 \
#      --no-cli-pager
