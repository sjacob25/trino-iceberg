#!/bin/bash

echo "Building Trino and Iceberg from GitHub sources..."

# Build custom Trino image
echo "Building Trino from source..."
docker build -t trino-iceberg-trino:source sources/trino/

# Build custom Iceberg image  
echo "Building Iceberg from source..."
docker build -t trino-iceberg-iceberg:source sources/iceberg/

echo "Source builds complete!"
echo ""
echo "To use source builds:"
echo "1. Update docker-compose.yml to use 'trino-iceberg-trino:source'"
echo "2. Run: docker-compose up -d"
