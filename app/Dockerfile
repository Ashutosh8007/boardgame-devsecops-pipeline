# ===== Build Stage =====
FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /app

# Copy pom.xml first to leverage Docker layer caching.
# This layer only invalidates when dependencies change, not on every source edit.
COPY pom.xml .
RUN mvn -B -q -DskipTests dependency:go-offline

# Copy source and build. Tests are intentionally skipped here because
# Jenkins runs the test stage separately, before this Docker build stage —
# duplicating test execution here would waste build time without adding safety.
COPY src ./src
RUN mvn clean package -DskipTests

# ===== Runtime Stage =====
FROM eclipse-temurin:17-jre-alpine

# Create a dedicated non-root user/group to run the application.
# Running containers as root is a real security risk: if the JVM process
# is ever compromised (e.g. via a dependency vulnerability), root inside
# the container has a much larger attack surface — including, depending on
# container runtime configuration, potential paths to host-level access.
RUN addgroup -S spring && adduser -S spring -G spring

WORKDIR /app

# Copy the built jar from the build stage only — none of the Maven/JDK
# build tooling makes it into this final image, keeping it small.
COPY --from=build /app/target/*.jar app.jar

# Ensure the non-root user owns the app files
RUN chown -R spring:spring /app

USER spring

EXPOSE 8080

# JVM tuning is explicit rather than left to defaults. On memory-constrained
# infrastructure (this app is destined for a Kubernetes pod with tight
# resource limits on a t2.micro node), an unbounded or auto-guessed heap
# size risks the JVM being OOM-killed by the container runtime rather than
# managing its own memory gracefully. -Xmx caps heap size explicitly;
# -XX:+UseSerialGC is the lightest-weight garbage collector, appropriate
# for a single-core, low-memory environment (the default G1GC assumes more
# CPU/memory headroom than we have here).
ENV JAVA_OPTS="-Xmx256m -Xms128m -XX:+UseSerialGC"

# Basic container-level healthcheck. This is separate from and simpler than
# the Kubernetes liveness/readiness probes we'll configure in Phase 9 —
# this one is useful for local `docker run` testing and for Docker Compose,
# if we use it, independent of Kubernetes.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD wget -q --spider http://localhost:8080/ || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
