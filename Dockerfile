# Optimized, multi-arch-friendly, secure Dockerfile for a Java 17 runnable JAR (recommended)
# - Uses Temurin jammy to stage the JAR; final runtime uses distroless nonroot.
# - Keep final image minimal and non-root.
FROM eclipse-temurin:17-jre-jammy AS extractor
ARG JAR_FILE=target/*.jar
WORKDIR /workspace
COPY ${JAR_FILE} app.jar
RUN [ -f /workspace/app.jar ]

FROM gcr.io/distroless/java17-debian11:nonroot
WORKDIR /app
COPY --from=extractor /workspace/app.jar /app/app.jar

# Container-aware JVM options (adjust as needed)
ENV JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]
