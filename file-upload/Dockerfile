# Use Amazon Corretto JDK 21 (lightweight & AWS-optimized)
FROM amazoncorretto:21-alpine AS runtime

# Set working directory
WORKDIR /app

# Copy JAR file (after Maven build)
COPY target/demo-0.0.1-SNAPSHOT.jar app.jar

# Expose Spring Boot default port
EXPOSE 8080

# Run the app
ENTRYPOINT ["java", "-jar", "app.jar"]
