# Trino Iceberg with PostgreSQL Catalog

Docker setup for running Trino queries on Iceberg tables with PostgreSQL catalog and MinIO storage.

## Quick Start

1. Start services:
```bash
docker-compose up -d
```

2. Wait for services to be ready (~30 seconds), then create MinIO bucket:
```bash
docker exec -it trino-iceberg-minio-1 mc mb /data/warehouse
```

3. Connect to Trino and run setup:
```bash
docker exec -it trino-iceberg-trino-1 trino --file /etc/trino/setup.sql
```

4. Query your data:
```bash
docker exec -it trino-iceberg-trino-1 trino --execute "SELECT * FROM iceberg.demo.orders"
```

## Services

- **Trino**: http://localhost:8080
- **MinIO Console**: http://localhost:9001 (minioadmin/minioadmin)
- **PostgreSQL**: localhost:5432 (iceberg/password)

## Cleanup

```bash
docker-compose down -v
```
