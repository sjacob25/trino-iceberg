# Apache Iceberg: Complete Guide from Basics to Advanced

## Table of Contents
1. [What is Apache Iceberg?](#what-is-apache-iceberg)
2. [Why Iceberg Matters](#why-iceberg-matters)
3. [Basic Concepts](#basic-concepts)
4. [Architecture Overview](#architecture-overview)
5. [Getting Started](#getting-started)
6. [Core Features](#core-features)
7. [Advanced Topics](#advanced-topics)
8. [Real-World Examples](#real-world-examples)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

## What is Apache Iceberg?

### Simple Explanation (Like You're 10)
Imagine you have a **magic filing cabinet** for your data:

```
Regular Filing Cabinet (Old databases):
📁 Folder 2023
   📄 January.xlsx
   📄 February.xlsx  
   📄 March.xlsx
   
Problems:
- Hard to find specific information across months
- Can't change folder structure easily
- Multiple people can't organize at same time
- No way to undo mistakes
```

```
Magic Filing Cabinet (Apache Iceberg):
📁 Sales Data
   🔍 Smart Index (knows what's in every file)
   📊 Schema (consistent structure)
   📸 Snapshots (can go back in time)
   🔄 ACID (safe changes)
   
Benefits:
- Instantly find any information
- Change structure without breaking anything
- Multiple people can work safely
- Travel back in time to see old data
```

### Technical Definition
Apache Iceberg is an **open table format** for huge analytic datasets that provides:
- **ACID transactions** for data lakes
- **Schema evolution** without breaking existing queries
- **Time travel** to query historical data
- **Partition evolution** to optimize performance over time
- **Multi-engine support** (Spark, Flink, Trino, etc.)

## Why Iceberg Matters

### The Data Lake Problem (Before Iceberg)

```
Traditional Data Lake Issues:

🏗️ Schema Problems:
   - Add new column → Break all existing queries
   - Change data type → Rewrite entire dataset
   - No schema validation → Corrupt data

🔄 Consistency Issues:
   - Multiple writers → Data corruption
   - Failed jobs → Partial data
   - No rollback → Permanent damage

📊 Performance Problems:
   - Query entire dataset for small results
   - No statistics → Poor query planning
   - Manual partition management

🕐 Operational Challenges:
   - No audit trail
   - Can't query historical data
   - Complex maintenance procedures
```

### The Iceberg Solution

```
Apache Iceberg Benefits:

✅ Schema Evolution:
   - Add columns safely
   - Change data types with compatibility
   - Automatic schema validation

✅ ACID Transactions:
   - Multiple writers work safely
   - All-or-nothing operations
   - Automatic rollback on failures

✅ Performance Optimization:
   - Automatic file pruning
   - Column-level statistics
   - Intelligent partition management

✅ Time Travel:
   - Query any historical state
   - Compare data across time
   - Audit and compliance support
```

## Basic Concepts

### 1. Table Format vs Database
```
Database (like PostgreSQL):
- Stores and manages data
- Provides query engine
- Handles transactions
- Manages storage

Table Format (like Iceberg):
- Defines how data is organized
- Works with any storage (S3, HDFS, etc.)
- Works with any engine (Spark, Trino, etc.)
- Provides metadata management
```

### 2. Key Components

#### Metadata Files
```
Table Structure:
my_table/
├── metadata/
│   ├── v1.metadata.json    ← Table definition
│   ├── v2.metadata.json    ← Updated definition
│   └── version-hint.text   ← Points to current version
├── data/
│   ├── year=2023/month=01/
│   │   ├── file1.parquet
│   │   └── file2.parquet
│   └── year=2023/month=02/
└── snapshots are tracked in metadata
```

#### Snapshots
```json
{
  "snapshot-id": 12345,
  "timestamp-ms": 1640995200000,
  "summary": {
    "operation": "append",
    "added-data-files": "5",
    "added-records": "1000000"
  },
  "manifest-list": "s3://bucket/table/metadata/snap-12345-manifest-list.avro"
}
```

#### Manifests
```
Manifest = List of data files with metadata
- File paths and sizes
- Partition information  
- Row counts and statistics
- Column min/max values
```

### 3. Schema Evolution Example

```sql
-- Day 1: Create table
CREATE TABLE sales (
    id BIGINT,
    product STRING,
    amount DOUBLE,
    sale_date DATE
) USING ICEBERG;

-- Day 30: Add customer info (safe!)
ALTER TABLE sales ADD COLUMN customer_id BIGINT;
ALTER TABLE sales ADD COLUMN customer_name STRING;

-- Day 60: Add nested data (safe!)
ALTER TABLE sales ADD COLUMN customer_details STRUCT<
    email: STRING,
    phone: STRING,
    address: STRUCT<
        street: STRING,
        city: STRING,
        country: STRING
    >
>;

-- All old queries still work!
SELECT product, amount FROM sales WHERE sale_date = '2023-01-01';
```

## Architecture Overview

### High-Level Architecture
```
┌─────────────────────────────────────────────────────┐
│                Query Engines                        │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐ │
│  │  Spark  │  │  Flink  │  │  Trino  │  │   Hive  │ │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘ │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────────┐
│              Apache Iceberg API                     │
│  ┌─────────────────────────────────────────────────┐ │
│  │            Table Operations                     │ │
│  │  • Read/Write  • Schema Evolution              │ │
│  │  • Time Travel • ACID Transactions             │ │
│  └─────────────────────────────────────────────────┘ │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────────┐
│                 Catalogs                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │   Hive   │  │   REST   │  │  Hadoop  │          │
│  │ Metastore│  │ Catalog  │  │ Catalog  │          │
│  └──────────┘  └──────────┘  └──────────┘          │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────────┐
│                  Storage                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │    S3    │  │   HDFS   │  │  Azure   │          │
│  │          │  │          │  │   Blob   │          │
│  └──────────┘  └──────────┘  └──────────┘          │
└─────────────────────────────────────────────────────┘
```

### Data Flow Example
```
1. User Query: "SELECT * FROM sales WHERE date = '2023-01-01'"

2. Query Engine (Spark):
   ├── Parses SQL
   ├── Calls Iceberg API
   └── Gets execution plan

3. Iceberg Table:
   ├── Reads current metadata
   ├── Finds relevant snapshots
   ├── Scans manifest files
   ├── Identifies data files for date = '2023-01-01'
   └── Returns file list to Spark

4. Spark Execution:
   ├── Reads only relevant Parquet files
   ├── Applies remaining filters
   └── Returns results to user

Result: Only reads 1 day of data instead of entire table!
```

## Getting Started

### 1. Basic Setup with Spark

```scala
// Spark configuration
val spark = SparkSession.builder()
  .appName("Iceberg Example")
  .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
  .config("spark.sql.catalog.spark_catalog", "org.apache.iceberg.spark.SparkSessionCatalog")
  .config("spark.sql.catalog.spark_catalog.type", "hive")
  .config("spark.sql.catalog.local", "org.apache.iceberg.spark.SparkCatalog")
  .config("spark.sql.catalog.local.type", "hadoop")
  .config("spark.sql.catalog.local.warehouse", "file:///tmp/warehouse")
  .getOrCreate()
```

### 2. Create Your First Table

```sql
-- Create table with partitioning
CREATE TABLE local.db.sales (
    id BIGINT,
    product STRING,
    category STRING,
    amount DOUBLE,
    sale_date DATE,
    sale_timestamp TIMESTAMP
) USING ICEBERG
PARTITIONED BY (days(sale_date));
```

### 3. Insert Data

```sql
-- Insert sample data
INSERT INTO local.db.sales VALUES
(1, 'Laptop', 'Electronics', 999.99, '2023-01-01', '2023-01-01 10:30:00'),
(2, 'Phone', 'Electronics', 599.99, '2023-01-01', '2023-01-01 11:15:00'),
(3, 'Book', 'Education', 29.99, '2023-01-02', '2023-01-02 09:45:00'),
(4, 'Tablet', 'Electronics', 399.99, '2023-01-02', '2023-01-02 14:20:00');
```

### 4. Query Data

```sql
-- Basic query
SELECT * FROM local.db.sales;

-- Filtered query (uses partition pruning)
SELECT * FROM local.db.sales WHERE sale_date = '2023-01-01';

-- Aggregation query
SELECT category, COUNT(*), SUM(amount) 
FROM local.db.sales 
GROUP BY category;
```

## Core Features

### 1. Time Travel

```sql
-- Query table as it was at specific time
SELECT * FROM local.db.sales TIMESTAMP AS OF '2023-01-01 12:00:00';

-- Query specific snapshot
SELECT * FROM local.db.sales VERSION AS OF 12345;

-- See all snapshots
SELECT * FROM local.db.sales.snapshots;

-- Compare data between snapshots
WITH current_data AS (
    SELECT * FROM local.db.sales
),
yesterday_data AS (
    SELECT * FROM local.db.sales TIMESTAMP AS OF current_timestamp() - INTERVAL 1 DAY
)
SELECT 
    c.id,
    c.amount as current_amount,
    y.amount as yesterday_amount,
    c.amount - y.amount as change
FROM current_data c
JOIN yesterday_data y ON c.id = y.id
WHERE c.amount != y.amount;
```

### 2. Schema Evolution

```sql
-- Add new column
ALTER TABLE local.db.sales ADD COLUMN customer_email STRING;

-- Rename column  
ALTER TABLE local.db.sales RENAME COLUMN product TO product_name;

-- Change column type (with compatibility)
ALTER TABLE local.db.sales ALTER COLUMN amount TYPE DECIMAL(10,2);

-- Drop column
ALTER TABLE local.db.sales DROP COLUMN category;

-- Add nested structure
ALTER TABLE local.db.sales ADD COLUMN shipping_address STRUCT<
    street: STRING,
    city: STRING,
    zip: STRING,
    country: STRING
>;
```

### 3. Partition Evolution

```sql
-- Start with daily partitioning
CREATE TABLE local.db.events (
    event_id BIGINT,
    event_type STRING,
    user_id BIGINT,
    event_time TIMESTAMP
) USING ICEBERG
PARTITIONED BY (days(event_time));

-- Later, change to hourly partitioning for better performance
ALTER TABLE local.db.events 
REPLACE PARTITION FIELD days(event_time) 
WITH hours(event_time);

-- Add additional partition field
ALTER TABLE local.db.events 
ADD PARTITION FIELD bucket(16, user_id);
```

### 4. ACID Transactions

```scala
// Scala example with transactions
import org.apache.iceberg._

val table = catalog.loadTable(TableIdentifier.of("db", "sales"))

// Start transaction
val transaction = table.newTransaction()

// Multiple operations in single transaction
transaction.newAppend()
  .appendFile(dataFile1)
  .appendFile(dataFile2)
  .commit()

transaction.updateSchema()
  .addColumn("new_column", Types.StringType.get())
  .commit()

// Commit entire transaction (atomic)
transaction.commitTransaction()
```
## Advanced Topics

### 1. Performance Optimization

#### File Size Optimization
```sql
-- Configure target file size (default: 512MB)
ALTER TABLE local.db.sales SET TBLPROPERTIES (
    'write.target-file-size-bytes' = '134217728'  -- 128MB
);

-- Compact small files
CALL local.system.rewrite_data_files(
    table => 'db.sales',
    options => map('target-file-size-bytes', '134217728')
);
```

#### Partition Pruning
```sql
-- Good: Uses partition pruning
SELECT * FROM sales WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31';

-- Bad: Scans all partitions
SELECT * FROM sales WHERE YEAR(sale_date) = 2023;

-- Better: Rewrite to use partition pruning
SELECT * FROM sales WHERE sale_date >= '2023-01-01' AND sale_date < '2024-01-01';
```

### 2. Real-World E-commerce Example

```sql
-- Create comprehensive e-commerce tables
CREATE TABLE ecommerce.orders (
    order_id BIGINT,
    customer_id BIGINT,
    product_id BIGINT,
    quantity INT,
    unit_price DECIMAL(10,2),
    total_amount DECIMAL(10,2),
    order_status STRING,
    order_date DATE,
    order_timestamp TIMESTAMP,
    shipping_address STRUCT<
        street: STRING,
        city: STRING,
        state: STRING,
        zip: STRING,
        country: STRING
    >
) USING ICEBERG
PARTITIONED BY (days(order_date), bucket(16, customer_id));

-- Daily sales analytics
SELECT 
    order_date,
    COUNT(DISTINCT order_id) as order_count,
    COUNT(DISTINCT customer_id) as unique_customers,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_order_value
FROM ecommerce.orders
WHERE order_date >= CURRENT_DATE - INTERVAL 30 DAYS
GROUP BY order_date
ORDER BY order_date;
```

### 3. Best Practices Summary

#### Table Design
- Use time-based partitioning for time-series data
- Choose appropriate data types
- Design for query patterns
- Avoid over-partitioning

#### Performance
- Set optimal file sizes (128MB-1GB)
- Use column pruning and predicate pushdown
- Regular maintenance (compaction, cleanup)
- Monitor query performance

#### Operations
- Implement snapshot retention policies
- Set up automated maintenance
- Monitor table health metrics
- Plan for schema evolution

## Conclusion

Apache Iceberg provides:
- **ACID Transactions** for reliable data operations
- **Schema Evolution** for adapting to changing requirements  
- **Time Travel** for historical data access
- **Multi-Engine Support** for flexibility
- **Performance Optimization** through intelligent file organization

It's the ideal choice for modern data lake architectures requiring reliability, performance, and flexibility.
