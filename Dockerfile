FROM trinodb/trino:latest

# Download and add PostgreSQL JDBC driver
USER root
RUN curl -o /usr/lib/trino/plugin/iceberg/postgresql.jar \
    https://jdbc.postgresql.org/download/postgresql-42.7.1.jar

USER trino
