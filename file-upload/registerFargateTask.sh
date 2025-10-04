echo ">>> Creating ECS cluster (if not exists)..."
aws ecs describe-clusters --clusters 'fargate-demo-cluster' --region 'us-west-1' \
  --query "clusters[?status=='ACTIVE'].clusterName" --output text | grep -w 'fargate-demo-cluster' || \
aws ecs create-cluster --cluster-name 'fargate-demo-cluster' --region 'us-west-1'

# ====== 6. Register Task Definition ======
echo ">>> Registering ECS task definition..."

aws ecs register-task-definition \
  --family fargate-java-demo-task \
  --cpu "512" --memory "1024" \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --execution-role-arn arn:aws:iam::523919781340:role/ecsTaskExecutionRole \
  --container-definitions '[
    {
      "name": "fargate-java-demo-container",
      "image": "523919781340.dkr.ecr.us-west-1.amazonaws.com/fargate-java21-demo:latest",
      "portMappings": [
        { "containerPort": 8080, "protocol": "tcp" }
      ],
      "essential": true
    }
  ]' \
  --region 'us-west-1'
