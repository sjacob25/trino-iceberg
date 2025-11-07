#!/usr/bin/env python3

from pyspark.sql import SparkSession

# Create Spark session with Iceberg support
spark = SparkSession.builder \
    .appName("Iceberg Demo") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.iceberg.type", "jdbc") \
    .config("spark.sql.catalog.iceberg.uri", "jdbc:postgresql://postgres:5432/iceberg") \
    .config("spark.sql.catalog.iceberg.jdbc.user", "iceberg") \
    .config("spark.sql.catalog.iceberg.jdbc.password", "password") \
    .config("spark.sql.catalog.iceberg.warehouse", "s3://warehouse/") \
    .config("spark.sql.catalog.iceberg.catalog-impl", "org.apache.iceberg.jdbc.JdbcCatalog") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "minioadmin") \
    .config("spark.hadoop.fs.s3a.secret.key", "minioadmin") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .getOrCreate()

print("Spark session created with Iceberg support!")
print("Available catalogs:")
spark.sql("SHOW CATALOGS").show()

print("\nTables in iceberg.sales schema:")
try:
    spark.sql("SHOW TABLES IN iceberg.sales").show()
except:
    print("No tables found or schema doesn't exist yet")

print("\nExample queries:")
print("spark.sql('SELECT * FROM iceberg.sales.transactions LIMIT 5').show()")
print("spark.sql('SELECT product_category, SUM(amount) as total FROM iceberg.sales.transactions GROUP BY product_category').show()")

# Keep session alive
spark.sparkContext.setLogLevel("WARN")
