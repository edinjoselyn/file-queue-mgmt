#!/bin/bash
set -e

REGION="us-west-1"
BUCKET="edin-bucket-523919781340"
QUEUE_NAME="s3-file-upload-queue"
LAMBDA_NAME="s3-email-lambda"
EMAIL_FROM="noreply@example.com"
EMAIL_TO="edin.joselyn@gmail.com"
ROLE_NAME="lambda-sqs-ses-role"

# 1. Create SQS if not exists
QUEUE_URL=$(aws sqs get-queue-url --queue-name $QUEUE_NAME --region $REGION --query 'QueueUrl' --output text 2>/dev/null || true)

if [ -z "$QUEUE_URL" ]; then
  echo "Creating SQS queue: $QUEUE_NAME"
  QUEUE_URL=$(aws sqs create-queue --queue-name $QUEUE_NAME --region $REGION --query 'QueueUrl' --output text)
else
  echo "SQS queue already exists: $QUEUE_NAME"
fi

QUEUE_ARN=$(aws sqs get-queue-attributes \
    --queue-url $QUEUE_URL \
    --attribute-names QueueArn \
    --region $REGION \
    --query 'Attributes.QueueArn' \
    --output text)

echo "Queue ARN: $QUEUE_ARN"

# 2. Set SQS policy to allow S3
POLICY_JSON=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "s3.amazonaws.com" },
      "Action": "sqs:SendMessage",
      "Resource": "$QUEUE_ARN",
      "Condition": {
        "ArnLike": { "aws:SourceArn": "arn:aws:s3:::$BUCKET" }
      }
    }
  ]
}
EOF
)

aws sqs set-queue-attributes \
  --queue-url $QUEUE_URL \
  --attributes "{\"Policy\": \"$(echo $POLICY_JSON | jq -c . | sed 's/\"/\\\"/g')\"}" \
  --region $REGION

# 3. Attach S3 → SQS event
aws s3api put-bucket-notification-configuration \
  --bucket $BUCKET \
  --region $REGION \
  --notification-configuration "{
    \"QueueConfigurations\": [
      {
        \"QueueArn\": \"$QUEUE_ARN\",
        \"Events\": [\"s3:ObjectCreated:*\"]

      }
    ]
  }"

# 4. Create IAM role for Lambda if not exists
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text 2>/dev/null || true)
if [ -z "$ROLE_ARN" ]; then
  echo "Creating IAM role: $ROLE_NAME"
  ROLE_ARN=$(aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": { "Service": "lambda.amazonaws.com" },
          "Action": "sts:AssumeRole"
        }
      ]
    }' \
    --query 'Role.Arn' --output text)

  aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess
  aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonSESFullAccess
else
  echo "IAM Role already exists: $ROLE_NAME"
fi

echo "Role ARN: $ROLE_ARN"

echo "✅ Setup complete: S3 → SQS"
