# Trino Iceberg Sales Analytics

Docker setup for running Trino queries on Iceberg tables with PostgreSQL catalog and MinIO storage, featuring sample sales data.

## Quick Start

Run the automated setup script:
```bash
./setup.sh
```

Or manually:

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

-- Top customers
SELECT c.customer_name, SUM(t.amount) as total_spent
FROM iceberg.sales.transactions t
JOIN iceberg.sales.customers c ON t.customer_id = c.customer_id
GROUP BY c.customer_name
ORDER BY total_spent DESC;
```

## Services

- **Trino**: http://localhost:8080
- **MinIO Console**: http://localhost:9001 (minioadmin/minioadmin)
- **PostgreSQL**: localhost:5432 (iceberg/password)

## Data Structure

- **Sales Transactions**: Product sales with customer, pricing, and location data
- **Customers**: Customer profiles with contact information
- **Storage**: All data stored in MinIO S3-compatible storage via Iceberg format

## Cleanup

```bash
docker-compose down -v
```
