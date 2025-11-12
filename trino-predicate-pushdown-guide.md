# Trino Predicate Pushdown: How Connectors Control Query Optimization

## Overview

Predicate pushdown is a critical optimization where Trino pushes filtering conditions (WHERE clauses) down to the data source instead of applying them after data retrieval. However, each connector implements different pushdown rules based on the capabilities and characteristics of the underlying data source.

## How Predicate Pushdown Works

### The Decision Process

```
User Query → Trino Parser → Connector Analysis → Pushdown Decision → Data Source Query
```

1. **Query Analysis**: Trino analyzes each predicate in the WHERE clause
2. **Connector Rules**: Each connector applies its specific pushdown rules
3. **SQL Generation**: Connector generates appropriate query for the data source
4. **Local Filtering**: Non-pushed predicates are applied in Trino workers

## PostgreSQL Connector

### Pushdown Rules

**✅ Safe to Push Down:**
- Equality predicates: `column = 'value'`
- IN clauses: `column IN ('a', 'b', 'c')`
- Inequality: `column != 'value'`
- Numeric range predicates: `age > 25`, `price BETWEEN 100 AND 500`

**❌ NOT Pushed Down:**
- String range predicates: `name > 'John'`, `name BETWEEN 'A' AND 'M'`
- Pattern matching on strings: `name LIKE 'J%'` (in some cases)

### Why String Ranges Aren't Pushed

```sql
-- PostgreSQL (with en_US.UTF-8 collation)
SELECT * FROM users WHERE name > 'Smith' ORDER BY name;
-- Result: ['Wilson', 'Young', 'Zeta']

-- Trino (with different collation rules)  
SELECT * FROM users WHERE name > 'Smith' ORDER BY name;
-- Result: ['Young', 'Wilson', 'Zeta']  -- Different order!
```

### Implementation Example

```java
// PostgreSqlClient.java
private boolean isSafeToPushDown(JdbcExpression expression) {
    if (isStringColumn(expression.getColumn()) && isRangeComparison(expression)) {
        return false;  // Don't include in SQL
    }
    return true;
}
```

### Query Examples

**Original Query:**
```sql
SELECT * FROM postgres.public.users WHERE name > 'John' AND id = 123;
```

**What Trino Sends to PostgreSQL:**
```sql
SELECT user_id, name, email FROM users WHERE id = 123;
```

**Trino Applies Locally:**
- Filters `name > 'John'` on the retrieved rows

## Iceberg Connector

### Pushdown Rules

**✅ Aggressive Pushdown:**
- All comparison operators: `=`, `!=`, `>`, `<`, `>=`, `<=`
- Range predicates: `BETWEEN`
- IN clauses: `column IN (values)`
- Pattern matching: `LIKE` patterns
- Date/timestamp predicates
- Partition pruning predicates

**✅ Advanced Features:**
- **Partition Pruning**: Automatically filters partitions
- **File Pruning**: Uses metadata to skip entire files
- **Column Pruning**: Only reads required columns

### Why Iceberg Pushdown is More Aggressive

```java
// Iceberg controls the file format and metadata
// No collation issues since Trino controls the sorting
public class IcebergMetadata implements ConnectorMetadata {
    
    @Override
    public Optional<ConstraintApplicationResult<ConnectorTableHandle>> applyFilter(...) {
        // Can safely push down all predicates
        // Iceberg metadata provides file-level statistics
        return pushDownAllPredicates(constraint);
    }
}
```

### Partition Pruning Example

**Table Structure:**
```
s3://data-lake/sales/
├── year=2023/
│   ├── month=01/part-001.parquet
│   └── month=02/part-002.parquet
└── year=2024/
    ├── month=01/part-003.parquet
    └── month=02/part-004.parquet
```

**Query:**
```sql
SELECT * FROM iceberg.warehouse.sales WHERE year = 2024 AND month = 1;
```

**Iceberg Optimization:**
- **Partition Pruning**: Only reads `year=2024/month=01/` directory
- **File Pruning**: Only processes `part-003.parquet`
- **Column Pruning**: Only reads requested columns from Parquet

### File-Level Statistics

```java
// Iceberg uses Parquet file statistics
if (fileStats.getMinValue("amount") > predicateValue) {
    // Skip entire file - no rows can match
    skipFile();
}
```

## Hive Connector

### Pushdown Rules

**✅ Pushed to Metastore:**
- Partition predicates: `year = 2024`, `region = 'US'`
- Simple equality on partition columns

**✅ Pushed to File Reading:**
- Column predicates on data columns
- Range predicates: `amount > 1000`
- Date predicates: `order_date >= '2024-01-01'`

**❌ Limited Pushdown:**
- Complex expressions
- User-defined functions
- Cross-partition aggregations

### Hive Partition Pruning

**Partitioned Table:**
```
hdfs://warehouse/orders/
├── year=2023/region=US/
├── year=2023/region=EU/
├── year=2024/region=US/
└── year=2024/region=EU/
```

**Query:**
```sql
SELECT * FROM hive.warehouse.orders 
WHERE year = 2024 AND region = 'US' AND amount > 1000;
```

**Hive Optimization:**
1. **Metastore Query**: Find partitions where `year=2024 AND region='US'`
2. **File Access**: Only read files in `year=2024/region=US/`
3. **File-Level Filtering**: Apply `amount > 1000` while reading Parquet/ORC

### Implementation Layers

```java
// HiveMetadata.java
public class HiveMetadata implements ConnectorMetadata {
    
    @Override
    public Optional<ConstraintApplicationResult<ConnectorTableHandle>> applyFilter(...) {
        
        // Separate partition vs data column predicates
        TupleDomain<ColumnHandle> partitionConstraint = extractPartitionConstraint(constraint);
        TupleDomain<ColumnHandle> dataConstraint = extractDataConstraint(constraint);
        
        // Push partition predicates to metastore
        List<HivePartition> prunedPartitions = metastore.getPartitions(
            table, partitionConstraint);
            
        // Push data predicates to file readers
        return Optional.of(new ConstraintApplicationResult<>(
            new HiveTableHandle(table, dataConstraint, prunedPartitions),
            TupleDomain.all()  // All constraints handled
        ));
    }
}
```

## Comparison Matrix

| Feature | PostgreSQL | Iceberg | Hive |
|---------|------------|---------|------|
| **String Range Predicates** | ❌ | ✅ | ✅ |
| **Numeric Predicates** | ✅ | ✅ | ✅ |
| **Partition Pruning** | N/A | ✅ | ✅ |
| **File Pruning** | N/A | ✅ | ✅ |
| **Column Pruning** | ✅ | ✅ | ✅ |
| **Pattern Matching** | Limited | ✅ | ✅ |
| **Complex Expressions** | Limited | ✅ | Limited |

## Performance Impact

### With Effective Pushdown
```sql
-- Iceberg: Only reads matching files
SELECT * FROM iceberg.sales WHERE year = 2024;
-- Reads: 12 files (1 year of data)
-- Network: 1GB transferred
```

### Without Pushdown
```sql
-- If pushdown failed
SELECT * FROM iceberg.sales WHERE year = 2024;
-- Reads: 120 files (10 years of data)  
-- Network: 10GB transferred
-- Filter applied in Trino workers
```

## Debugging Pushdown

### Using EXPLAIN

```sql
EXPLAIN (TYPE DISTRIBUTED) 
SELECT * FROM postgres.public.users WHERE name > 'John' AND id = 123;
```

**Output Analysis:**
- **TableScan[postgres:users, constraint=id=123]** → `id` predicate pushed down
- **Filter: name > 'John'** → `name` predicate applied in Trino

### Connector-Specific Logging

**Enable debug logging:**
```properties
# log.properties
io.trino.plugin.postgresql=DEBUG
io.trino.plugin.iceberg=DEBUG
io.trino.plugin.hive=DEBUG
```

**Log Output:**
```
DEBUG: Pushing down predicate: id = 123
DEBUG: Not pushing down predicate: name > 'John' (string range comparison)
DEBUG: Generated SQL: SELECT * FROM users WHERE id = 123
```

## Best Practices

### Query Design

**✅ Optimize for Pushdown:**
```sql
-- Use partition columns in WHERE clauses
SELECT * FROM iceberg.sales WHERE year = 2024 AND month = 1;

-- Use equality predicates on string columns
SELECT * FROM postgres.users WHERE status = 'active';

-- Use numeric ranges freely
SELECT * FROM hive.orders WHERE amount BETWEEN 100 AND 1000;
```

**❌ Avoid Pushdown Blockers:**
```sql
-- String ranges (PostgreSQL)
SELECT * FROM postgres.users WHERE name > 'John';

-- Complex expressions
SELECT * FROM any_connector.table WHERE UPPER(column) = 'VALUE';

-- Functions in WHERE clauses
SELECT * FROM any_connector.table WHERE DATE_FORMAT(date_col, '%Y') = '2024';
```

### Monitoring

**Track pushdown effectiveness:**
```sql
-- Check query plans regularly
EXPLAIN (TYPE DISTRIBUTED) SELECT ...;

-- Monitor data transfer volumes
-- High network I/O may indicate poor pushdown
```

## Conclusion

Understanding predicate pushdown behavior is crucial for Trino query performance. Each connector implements pushdown rules based on:

1. **Data source capabilities** (SQL features, APIs)
2. **Correctness requirements** (collation, data types)
3. **Performance characteristics** (partition pruning, file formats)

The key is to design queries that align with each connector's pushdown strengths while avoiding patterns that force expensive data transfers and local filtering.
