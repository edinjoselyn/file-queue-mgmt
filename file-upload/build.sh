# Build JAR
mvn clean package -DskipTests

# Build Docker image
docker build -t fargate-java21-demo .

# Create ECR repo (only once)
aws ecr create-repository --repository-name fargate-java21-demo

# Authenticate Docker
aws ecr get-login-password --region us-west-1 | \
  docker login --username AWS --password-stdin 523919781340.dkr.ecr.us-west-1.amazonaws.com

# Tag & Push
docker tag fargate-java21-demo:latest 523919781340.dkr.ecr.us-west-1.amazonaws.com/fargate-java21-demo:latest
docker push 523919781340.dkr.ecr.us-west-1.amazonaws.com/fargate-java21-demo:latest
