#!/bin/bash

echo "Starting Trino + Spark Iceberg setup..."

# Start Docker services
docker-compose up -d

echo "Waiting for services to start..."
sleep 30

# Create MinIO buckets
echo "Creating MinIO warehouse buckets..."
docker exec trino-iceberg-minio-1 mc mb /data/warehouse 2>/dev/null || true
docker exec trino-iceberg-minio-hr-1 mc mb /data/hr-warehouse 2>/dev/null || true

# Wait for Trino to be ready
echo "Waiting for Trino to be ready..."
sleep 15

# Setup sample data via Trino
echo "Setting up sample data..."
docker exec trino-iceberg-trino-1 trino --file /setup.sql

echo ""
echo "Setup complete! All services are ready."
echo ""
echo "Services available:"
echo "- Trino: http://localhost:8081"
echo "- Spark UI: http://localhost:8082"
echo "- Superset: http://localhost:8088 (admin/admin)"
echo "- Sales MinIO Console: http://localhost:9001 (minioadmin/minioadmin)"
echo "- HR MinIO Console: http://localhost:9004 (hradmin/hradmin123)"
echo "- PostgreSQL: localhost:5434 (iceberg/password)"
echo ""
echo "Connect to:"
echo "- Trino: docker exec -it trino-iceberg-trino-1 trino"
echo "- Spark: docker exec -it trino-iceberg-spark-1 python /setup-spark.py"
echo ""
echo "Superset Database Connections:"
echo "- Trino Iceberg: trino://trino:8080/iceberg"
echo "- Trino HR: trino://trino:8080/iceberg_hr"  
echo "- PostgreSQL: postgresql://iceberg:password@postgres:5432/iceberg"
echo ""
echo "All engines share the same Iceberg tables via PostgreSQL catalog!"
