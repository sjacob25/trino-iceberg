FROM maven:3.9-openjdk-21 AS builder

# Clone Trino source
RUN git clone https://github.com/trinodb/trino.git /trino-source
WORKDIR /trino-source

# Build Trino (using specific tag for stability)
RUN git checkout 458
RUN ./mvnw clean install -DskipTests -Dair.check.skip-all

FROM openjdk:21-jre-slim

# Copy built Trino
COPY --from=builder /trino-source/core/trino-server/target/trino-server-*/ /usr/lib/trino/

# Add PostgreSQL driver
RUN curl -o /usr/lib/trino/plugin/iceberg/postgresql.jar \
    https://jdbc.postgresql.org/download/postgresql-42.7.1.jar

# Create trino user
RUN groupadd trino && useradd -g trino trino
RUN chown -R trino:trino /usr/lib/trino

USER trino
EXPOSE 8080
CMD ["/usr/lib/trino/bin/launcher", "run"]
