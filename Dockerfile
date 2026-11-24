# Build stage: compile the ShinyProxy JAR from source
FROM public.ecr.aws/docker/library/maven:3.9-eclipse-temurin-21 AS builder

# Fail fast on stalled repository connections (default request timeout is 30 min, and a
# single hung request to nexus.openanalytics.eu stalled a CI build for ~47 min). Stalled
# requests now time out after 60s and are retried by the resolver.
ENV MAVEN_OPTS="-Daether.connector.connectTimeout=10000 -Daether.connector.requestTimeout=60000"

WORKDIR /build
COPY pom.xml LICENSE_HEADER ./
# Cache dependencies
RUN mvn dependency:go-offline -B || true
COPY src ./src
RUN mvn package -DskipTests -B && \
    cp target/shinyproxy-*-exec.jar /opt/shinyproxy.jar

# Final image: matches upstream openanalytics/shinyproxy structure
# Pinned to a Temurin build containing the Java4Shell fix (CVE-2026-114938, fixed in 21.0.13.1+2).
FROM public.ecr.aws/docker/library/eclipse-temurin:21.0.13.1_2-jre-noble

LABEL maintainer="IntegralEnvision"
ENV SHINY_USER=shinyproxy

RUN useradd -c 'shinyproxy user' -m -d /home/$SHINY_USER -s /sbin/nologin $SHINY_USER && \
    mkdir -p /opt/shinyproxy && \
    chown $SHINY_USER:$SHINY_USER /opt/shinyproxy

COPY --from=builder --chown=$SHINY_USER:$SHINY_USER /opt/shinyproxy.jar /opt/shinyproxy/shinyproxy.jar

WORKDIR /opt/shinyproxy
USER $SHINY_USER

# -XX:-UseBASE64Intrinsics: defence-in-depth for CVE-2026-114938 (disables the vulnerable
# AVX-512 Base64 intrinsic); matches upstream openanalytics/shinyproxy images.
CMD ["java", "-XX:-UseBASE64Intrinsics", "-Dsun.net.inetaddr.ttl=5", "-XX:MaxRAMPercentage=50.0", "-XX:MinRAMPercentage=20.0", "-XX:+ExitOnOutOfMemoryError", "-jar", "/opt/shinyproxy/shinyproxy.jar", "--spring.jmx.enabled=false", "--spring.config.location=/opt/shinyproxy/application.yml"]
