  aws ecs create-service \
    --cluster fargate-demo-cluster \
    --service-name fargate-java-demo-service \
    --task-definition fargate-java-demo-task \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[subnet-ab1a0af0],securityGroups=[sg-5259f92d],assignPublicIp=ENABLED}" \
    --region 'us-west-1'

echo "✅ Deployment complete! Your Java 21 REST API is running on Fargate."