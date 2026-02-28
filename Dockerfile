# Example Dockerfile for a Maven-built fat/uber JAR
# It expects the built jar to be supplied at build time via build-arg JAR_FILE
FROM eclipse-temurin:17-jre-alpine AS runtime

ARG JAR_FILE=target/*.jar
WORKDIR /app

# Copy the JAR (the workflow builds and passes artifact into the build context)
# When using docker build locally, ensure a JAR exists at the specified path.
COPY ${JAR_FILE} app.jar

ENV JAVA_OPTS=""
EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]