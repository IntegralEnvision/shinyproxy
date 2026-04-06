# Build stage: compile the ShinyProxy JAR from source
FROM public.ecr.aws/docker/library/maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /build
COPY pom.xml LICENSE_HEADER ./
# Cache dependencies
RUN mvn dependency:go-offline -B || true
COPY src ./src
RUN mvn package -DskipTests -B && \
    cp target/shinyproxy-*-exec.jar /opt/shinyproxy.jar

# Final image: matches upstream openanalytics/shinyproxy structure
FROM public.ecr.aws/docker/library/eclipse-temurin:21-jre-noble

LABEL maintainer="IntegralEnvision"
ENV SHINY_USER=shinyproxy

RUN useradd -c 'shinyproxy user' -m -d /home/$SHINY_USER -s /sbin/nologin $SHINY_USER && \
    mkdir -p /opt/shinyproxy && \
    chown $SHINY_USER:$SHINY_USER /opt/shinyproxy

COPY --from=builder --chown=$SHINY_USER:$SHINY_USER /opt/shinyproxy.jar /opt/shinyproxy/shinyproxy.jar

WORKDIR /opt/shinyproxy
USER $SHINY_USER

CMD ["java", "-Dsun.net.inetaddr.ttl=5", "-XX:MaxRAMPercentage=50.0", "-XX:MinRAMPercentage=20.0", "-XX:+ExitOnOutOfMemoryError", "-jar", "/opt/shinyproxy/shinyproxy.jar", "--spring.jmx.enabled=false", "--spring.config.location=/opt/shinyproxy/application.yml"]

