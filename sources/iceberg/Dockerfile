FROM openjdk:11-jdk AS builder

# Install dependencies
RUN apt-get update && apt-get install -y git

# Clone Iceberg source
RUN git clone https://github.com/apache/iceberg.git /iceberg-source
WORKDIR /iceberg-source

# Build Iceberg (using specific tag for stability)
RUN git checkout apache-iceberg-1.4.3
RUN ./gradlew build -x test

FROM openjdk:11-jre-slim

# Copy built Iceberg libraries
COPY --from=builder /iceberg-source/build/libs/ /opt/iceberg/libs/

# Create iceberg user
RUN groupadd iceberg && useradd -g iceberg iceberg
RUN chown -R iceberg:iceberg /opt/iceberg

USER iceberg
WORKDIR /opt/iceberg
