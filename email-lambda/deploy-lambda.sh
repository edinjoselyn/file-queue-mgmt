#!/bin/bash
set -e

# ===== CONFIG =====
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
FUNCTION_NAME="s3-email-lambda"
QUEUE_NAME="s3-file-upload-queue"
#ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/lambda-s3-ses-role"
HANDLER="com.example.lambda.S3EmailHandler::handleRequest"
SQS_ARN="arn:aws:sqs:us-west-1:${ACCOUNT_ID}:${QUEUE_NAME}"
REGION="us-west-1"
JAR_FILE="target/email-lambda-1.0-SNAPSHOT.jar"
LAMBDA_ROLE=lambda-s3-ses-role

# ===== BUILD =====
echo ">>> Building Lambda JAR..."
mvn clean package -DskipTests

# ===== Create/Update IAM Role =====
ROLE_ARN=$(aws iam get-role --role-name $LAMBDA_ROLE --query "Role.Arn" --output text 2>/dev/null || true)

if [ -z "$ROLE_ARN" ]; then
  echo "Role does not exist, creating..."
  aws iam create-role \
    --role-name ${LAMBDA_ROLE} \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "lambda.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }'
else
  echo "Role exists: $ROLE_ARN"
fi

aws iam attach-role-policy \
  --role-name ${LAMBDA_ROLE} \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam attach-role-policy \
  --role-name ${LAMBDA_ROLE} \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

aws iam attach-role-policy \
  --role-name ${LAMBDA_ROLE} \
  --policy-arn arn:aws:iam::aws:policy/AmazonSESFullAccess

aws iam attach-role-policy \
  --role-name ${LAMBDA_ROLE} \
  --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess

aws iam put-role-policy \
  --role-name lambda-s3-ses-role \
  --policy-name LambdaSQSPollPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ],
        "Resource": "arn:aws:sqs:us-west-1:523919781340:s3-file-upload-queue"
      }
    ]
  }'

ROLE_ARN=$(aws iam get-role --role-name ${LAMBDA_ROLE} --query "Role.Arn" --output text)

# ===== CHECK IF FUNCTION EXISTS =====
echo ">>> Checking if Lambda exists..."
if aws lambda get-function --function-name "$FUNCTION_NAME" --region $REGION >/dev/null 2>&1; then
    echo ">>> Updating existing Lambda..."

    aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --handler "$HANDLER" \
        --region $REGION

    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file fileb://$JAR_FILE \
        --region $REGION
else
    echo ">>> Creating new Lambda..."
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime java21 \
        --role "$ROLE_ARN" \
        --handler "$HANDLER" \
        --zip-file fileb://$JAR_FILE \
        --memory-size 512 \
        --timeout 30 \
        --region $REGION
fi

# ===== EVENT SOURCE MAPPING =====
echo ">>> Checking for event source mapping..."
UUID=$(aws lambda list-event-source-mappings \
    --function-name "$FUNCTION_NAME" \
    --region $REGION \
    --query "EventSourceMappings[?EventSourceArn=='$SQS_ARN'].UUID" \
    --output text)

if [ "$UUID" == "None" ] || [ -z "$UUID" ]; then
    echo ">>> Creating event source mapping..."
    aws lambda create-event-source-mapping \
        --function-name "$FUNCTION_NAME" \
        --event-source-arn "$SQS_ARN" \
        --batch-size 1 \
        --enabled \
        --region $REGION
else
    echo ">>> Event source mapping already exists (UUID=$UUID)"
fi

echo ">>> ✅ Deployment finished!"
