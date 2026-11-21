# Build stage: compile the ShinyProxy JAR from source
FROM public.ecr.aws/docker/library/maven:3.9-eclipse-temurin-21 AS builder

# ShinyProxy >= 3.2.5 (Spring Boot 4) depends on io.undertow:undertow-spring-boot-starter:1.0.0-SNAPSHOT,
# which is not published to any public Maven repo. Upstream builds it from the `spring-boot-undertow`
# git submodule. Our CI checkout does not fetch submodules, so fetch the exact commit the submodule
# pins (keep in sync with `git ls-tree HEAD spring-boot-undertow` when merging upstream releases).
ADD https://github.com/jboss-fuse/spring-boot-undertow.git#f7313fea63a478e5732a2f04d1e6911a04a59ea5 /build/spring-boot-undertow
RUN cd /build/spring-boot-undertow && mvn -B -q -DskipTests clean install

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
