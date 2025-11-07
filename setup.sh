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
sleep 15

# Test Trino connection and create sample data
echo "Testing Trino connection and creating sample data..."
docker exec trino-iceberg-trino-1 trino --execute "
CREATE TABLE memory.default.sales_transactions (
    transaction_id BIGINT,
    customer_name VARCHAR(100),
    product_name VARCHAR(100),
    product_category VARCHAR(50),
    amount DECIMAL(10,2),
    transaction_date DATE
);

INSERT INTO memory.default.sales_transactions VALUES
(1001, 'Alice Johnson', 'Business Laptop Pro', 'Electronics', 1299.99, DATE '2024-01-15'),
(1002, 'Bob Smith', 'Smartphone X', 'Electronics', 899.99, DATE '2024-01-16'),
(1003, 'Carol Davis', 'Standing Desk', 'Furniture', 599.99, DATE '2024-01-17'),
(1004, 'David Wilson', 'Ergonomic Chair', 'Furniture', 299.99, DATE '2024-01-18'),
(1005, 'Eva Brown', '4K Monitor', 'Electronics', 449.99, DATE '2024-01-19');

SELECT 'Sample Data Created Successfully' as status;
"

echo ""
echo "Setup complete! Trino is ready for queries."
echo ""
echo "Connect to Trino:"
echo "docker exec -it trino-iceberg-trino-1 trino"
echo ""
echo "Sample queries:"
echo "SHOW CATALOGS;"
echo "SELECT * FROM memory.default.sales_transactions;"
echo "SELECT product_category, SUM(amount) FROM memory.default.sales_transactions GROUP BY product_category;"
