#!/bin/bash
set -e

# --- CONFIGURATION ---
CLUSTER_NAME="fargate-demo-cluster"
SERVICE_NAME="fargate-java21-service"
TASK_DEFINITION="fargate-java21-task"
REGION="us-west-1"
S3_BUCKET="your-bucket-name"
ACCOUNT_ID="523919781340"
ROLE_NAME="ecsTaskRole"
POLICY_NAME="S3UploadPolicy"

# --- 1️⃣ Create ECS task role if not exists ---
if ! aws iam get-role --role-name $ROLE_NAME --region $REGION >/dev/null 2>&1; then
    echo "Creating task role $ROLE_NAME..."
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document '{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": { "Service": "ecs-tasks.amazonaws.com" },
              "Action": "sts:AssumeRole"
            }
          ]
        }' \
        --region $REGION
else
    echo "Task role $ROLE_NAME already exists."
fi

# --- 2️⃣ Attach S3 policy ---
echo "Attaching S3 upload policy..."
aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name $POLICY_NAME \
    --policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Action\": [\"s3:PutObject\",\"s3:PutObjectAcl\"],
          \"Resource\": \"arn:aws:s3:::$S3_BUCKET/*\"
        }
      ]
    }" \
    --region $REGION

# --- 3️⃣ Create new task definition revision ---
echo "Fetching current task definition..."
aws ecs describe-task-definition \
    --task-definition $TASK_DEFINITION \
    --region $REGION \
    --query "taskDefinition" \
    --output json > task-def.json

echo "Modifying task role in task definition..."
jq 'del(.status, .revision, .taskDefinitionArn, .requiresAttributes, .registeredAt, .registeredBy) | .taskRoleArn="arn:aws:iam::'$ACCOUNT_ID':role/'$ROLE_NAME'"' task-def.json > task-def-updated.json

echo "Registering new task definition revision..."
aws ecs register-task-definition \
    --cli-input-json file://task-def-updated.json \
    --region $REGION

# --- 4️⃣ Update ECS service ---
NEW_REV=$(aws ecs describe-task-definition \
    --task-definition $TASK_DEFINITION \
    --region $REGION \
    --query "taskDefinition.revision" \
    --output text)

echo "Updating ECS service to use new revision..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --task-definition $TASK_DEFINITION:$NEW_REV \
    --force-new-deployment \
    --platform-version LATEST \
    --region $REGION \
    --no-cli-pager

# --- 5️⃣ Wait a bit and get public IP ---
echo "Waiting for task to launch..."
sleep 15

TASK_ARN=$(aws ecs list-tasks \
    --cluster $CLUSTER_NAME \
    --service-name $SERVICE_NAME \
    --region $REGION \
    --query "taskArns[0]" \
    --output text)

PUBLIC_IP=$(aws ecs describe-tasks \
    --cluster $CLUSTER_NAME \
    --tasks $TASK_ARN \
    --region $REGION \
    --query "tasks[0].attachments[0].details[?name=='publicIPv4Address'].value" \
    --output text)

echo "Task public IP: $PUBLIC_IP"
echo "Test upload with:"
echo "curl -X POST -F \"file=@/path/to/file.txt\" http://$PUBLIC_IP:8080/api/upload"
