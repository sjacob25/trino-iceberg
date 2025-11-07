# Trino Iceberg Sales Analytics

Docker setup for running Trino queries on Iceberg tables with PostgreSQL catalog and MinIO storage, featuring sample sales data, Spark integration, and Superset dashboards.

## Quick Start

Run the automated setup script:
```bash
./setup.sh
```

## Build from GitHub Sources

To build Trino and Iceberg from GitHub sources:

```bash
# Build from source (takes 15-30 minutes)
./build-from-source.sh

# Or use development build (faster)
docker build -t trino-custom sources/trino/ -f sources/trino/Dockerfile.dev
```

## Source Structure

```
sources/
├── trino/
│   ├── Dockerfile          # Full build from GitHub
│   └── Dockerfile.dev      # Development build
└── iceberg/
    └── Dockerfile          # Iceberg from GitHub
```

## Manual Setup

1. Start services: `docker-compose up -d`
2. Wait 30 seconds, then: `docker exec trino-iceberg-minio-1 mc mb /data/warehouse`
3. Setup data: `docker exec trino-iceberg-trino-1 trino --file /setup.sql`

## Sample Queries

Connect to Trino:
```bash
docker exec -it trino-iceberg-trino-1 trino
```

Query sales data:
```sql
-- View all transactions
SELECT * FROM iceberg.sales.transactions LIMIT 10;

-- Sales by category
SELECT product_category, SUM(amount) as total_sales 
FROM iceberg.sales.transactions 
GROUP BY product_category;

-- Cross-catalog join
SELECT t.product_name, c.customer_name, t.amount
FROM iceberg.sales.transactions t
JOIN postgresql.analytics.customers c ON t.customer_id = c.customer_id;
```

## Services

- **Trino**: http://localhost:8081
- **Spark UI**: http://localhost:8082
- **Superset**: http://localhost:8088 (admin/admin)
- **Sales MinIO Console**: http://localhost:9001 (minioadmin/minioadmin)
- **HR MinIO Console**: http://localhost:9004 (hradmin/hradmin123)
- **PostgreSQL**: localhost:5434 (iceberg/password)

## Data Structure

- **Sales Transactions**: Product sales with customer, pricing, and location data (Main MinIO)
- **HR Employees**: Employee information (Isolated HR MinIO)
- **Customers**: Customer profiles in PostgreSQL
- **Storage**: Data stored across multiple MinIO instances via Iceberg format

## Catalogs

- `iceberg` - Sales data in main MinIO
- `iceberg_hr` - HR data in isolated MinIO
- `postgresql` - Direct PostgreSQL access
- `memory` - In-memory tables

## Superset Database Connections

Add these connections in Superset UI:

1. **Trino Iceberg**: `trino://trino:8080/iceberg`
2. **Trino HR**: `trino://trino:8080/iceberg_hr`
3. **Trino PostgreSQL**: `trino://trino:8080/postgresql`
4. **Direct PostgreSQL**: `postgresql://iceberg:password@postgres:5432/iceberg`
5. **Trino Memory**: `trino://trino:8080/memory`

## Cleanup

```bash
docker-compose down -v
```
