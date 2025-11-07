#!/bin/bash

echo "Starting Trino Iceberg setup..."

# Start Docker services
docker-compose up -d

echo "Waiting for services to start..."
sleep 30

# Create MinIO bucket
echo "Creating MinIO warehouse bucket..."
docker exec trino-iceberg-minio-1 mc mb /data/warehouse

# Wait for Trino to be ready
echo "Waiting for Trino to be ready..."
sleep 10

# Run setup SQL
echo "Creating schemas and sample data..."
docker exec trino-iceberg-trino-1 trino --file /setup.sql

echo "Setup complete! You can now query data:"
echo "docker exec -it trino-iceberg-trino-1 trino"
echo ""
echo "Sample queries:"
echo "SHOW SCHEMAS FROM iceberg;"
echo "SELECT * FROM iceberg.sales.transactions LIMIT 10;"
echo "SELECT product_category, SUM(amount) FROM iceberg.sales.transactions GROUP BY product_category;"
