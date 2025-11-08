# On-Premises Data Pipeline Architecture: Industry Best Practices

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Data Ingestion Strategies](#data-ingestion-strategies)
3. [Change Data Capture (CDC)](#change-data-capture-cdc)
4. [Stream Processing](#stream-processing)
5. [Data Lake Architecture](#data-lake-architecture)
6. [ETL/ELT Patterns](#etlelt-patterns)
7. [Data Quality & Governance](#data-quality--governance)
8. [Monitoring & Operations](#monitoring--operations)
9. [Real-World Case Studies](#real-world-case-studies)

## Architecture Overview

### Modern Data Pipeline Architecture
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DATA SOURCES                                      │
├─────────────────┬─────────────────┬─────────────────┬─────────────────────┤
│   PostgreSQL    │      MySQL      │      Kafka      │    Web Services     │
│   Oracle        │   SQL Server    │   Event Logs    │    File Systems     │
└─────────────────┴─────────────────┴─────────────────┴─────────────────────┘
         │                 │                 │                 │
         ▼                 ▼                 ▼                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        INGESTION LAYER                                     │
├─────────────────┬─────────────────┬─────────────────┬─────────────────────┤
│   Debezium      │    Sqoop        │  Kafka Connect  │      Flume          │
│   Maxwell       │    Airbyte      │  Custom APIs    │      NiFi           │
└─────────────────┴─────────────────┴─────────────────┴─────────────────────┘
         │                 │                 │                 │
         ▼                 ▼                 ▼                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      MESSAGE QUEUE / STREAMING                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                    Apache Kafka / Pulsar                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      STREAM PROCESSING                                     │
├─────────────────┬─────────────────┬─────────────────┬─────────────────────┤
│  Apache Flink   │  Apache Spark   │ Apache Storm    │   Kafka Streams     │
│  (Real-time)    │  (Batch/Stream) │  (Real-time)    │   (Lightweight)     │
└─────────────────┴─────────────────┴─────────────────┴─────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         STORAGE LAYER                                      │
├─────────────────┬─────────────────┬─────────────────┬─────────────────────┤
│      HDFS       │       S3        │   Object Store  │      Hive           │
│   (Raw Data)    │  (Processed)    │   (MinIO/Ceph)  │   (Metadata)        │
└─────────────────┴─────────────────┴─────────────────┴─────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       ANALYTICS LAYER                                      │
├─────────────────┬─────────────────┬─────────────────┬─────────────────────┤
│   Apache Spark  │     Trino       │    Apache Drill │      Hive           │
│   (Processing)  │   (Query Eng)   │   (Query Eng)   │   (Warehouse)       │
└─────────────────┴─────────────────┴─────────────────┴─────────────────────┘
```

### Technology Stack Comparison
| Component | Options | Pros | Cons | Best For |
|-----------|---------|------|------|----------|
| **CDC** | Debezium | Real-time, reliable | Complex setup | RDBMS changes |
| | Maxwell | Simple, MySQL focus | MySQL only | MySQL environments |
| **Streaming** | Kafka | High throughput, durable | Operational complexity | High-volume streams |
| | Pulsar | Multi-tenancy, geo-replication | Newer, smaller community | Multi-tenant scenarios |
| **Processing** | Flink | Low latency, exactly-once | Steep learning curve | Real-time analytics |
| | Spark | Mature, versatile | Higher latency | Batch + streaming |
| **Storage** | HDFS | Proven, integrated | Single point of failure | Large datasets |
| | MinIO | S3-compatible, simple | Less mature | S3 replacement |

## Data Ingestion Strategies

### 1. Database Change Data Capture (CDC)

#### Debezium Implementation
```yaml
# docker-compose.yml for Debezium
version: '3.8'
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:latest
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181

  kafka:
    image: confluentinc/cp-kafka:latest
    depends_on: [zookeeper]
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092

  connect:
    image: debezium/connect:latest
    depends_on: [kafka]
    environment:
      BOOTSTRAP_SERVERS: kafka:9092
      GROUP_ID: 1
      CONFIG_STORAGE_TOPIC: connect_configs
      OFFSET_STORAGE_TOPIC: connect_offsets
    ports:
      - 8083:8083
```

#### PostgreSQL CDC Configuration
```json
{
  "name": "postgres-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "postgres-server",
    "database.port": "5432",
    "database.user": "debezium_user",
    "database.password": "debezium_password",
    "database.dbname": "production_db",
    "database.server.name": "prod-postgres",
    "table.include.list": "public.orders,public.customers,public.products",
    "plugin.name": "pgoutput",
    "slot.name": "debezium_slot",
    "publication.name": "debezium_publication",
    "transforms": "route",
    "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.route.regex": "([^.]+)\\.([^.]+)\\.([^.]+)",
    "transforms.route.replacement": "$3"
  }
}
```

#### MySQL CDC with Maxwell
```bash
# Maxwell configuration
# maxwell.properties
log_level=info
producer=kafka
kafka.bootstrap.servers=localhost:9092

# MySQL connection
host=mysql-server
port=3306
user=maxwell
password=maxwell_password
schema_database=maxwell

# Filter configuration
filter=exclude: *.*, include: ecommerce.orders, ecommerce.customers
output_ddl=true
```

### 2. Batch Data Ingestion

#### Apache Sqoop for RDBMS
```bash
# Full table import
sqoop import \
  --connect jdbc:postgresql://postgres-server:5432/ecommerce \
  --username sqoop_user \
  --password sqoop_password \
  --table orders \
  --target-dir /data/raw/orders \
  --file-format parquet \
  --compression-codec snappy \
  --num-mappers 4

# Incremental import
sqoop import \
  --connect jdbc:postgresql://postgres-server:5432/ecommerce \
  --username sqoop_user \
  --password sqoop_password \
  --table orders \
  --target-dir /data/raw/orders \
  --incremental append \
  --check-column order_id \
  --last-value 1000000 \
  --file-format parquet
```

#### Airbyte Configuration
```yaml
# airbyte-postgres-source.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-source-config
data:
  config.json: |
    {
      "host": "postgres-server",
      "port": 5432,
      "database": "ecommerce",
      "username": "airbyte_user",
      "password": "airbyte_password",
      "ssl": false,
      "replication_method": {
        "method": "CDC",
        "replication_slot": "airbyte_slot",
        "publication": "airbyte_publication"
      },
      "schemas": ["public"],
      "tunnel_method": {
        "tunnel_method": "NO_TUNNEL"
      }
    }
```

### 3. API Data Ingestion

#### Custom API Connector
```python
# api_ingestion.py
import requests
import json
import time
from kafka import KafkaProducer
from datetime import datetime, timedelta

class APIIngestionService:
    def __init__(self, kafka_bootstrap_servers, api_config):
        self.producer = KafkaProducer(
            bootstrap_servers=kafka_bootstrap_servers,
            value_serializer=lambda v: json.dumps(v).encode('utf-8')
        )
        self.api_config = api_config
    
    def ingest_api_data(self, endpoint, topic_name):
        """Ingest data from REST API to Kafka"""
        try:
            # API call with pagination
            page = 1
            while True:
                response = requests.get(
                    f"{self.api_config['base_url']}/{endpoint}",
                    params={
                        'page': page,
                        'limit': 1000,
                        'api_key': self.api_config['api_key']
                    },
                    timeout=30
                )
                
                if response.status_code != 200:
                    break
                
                data = response.json()
                if not data.get('results'):
                    break
                
                # Send to Kafka
                for record in data['results']:
                    record['ingestion_timestamp'] = datetime.utcnow().isoformat()
                    self.producer.send(topic_name, record)
                
                page += 1
                time.sleep(0.1)  # Rate limiting
                
        except Exception as e:
            print(f"Error ingesting from {endpoint}: {e}")
        finally:
            self.producer.flush()

# Usage
api_config = {
    'base_url': 'https://api.example.com/v1',
    'api_key': 'your-api-key'
}

ingestion_service = APIIngestionService(['localhost:9092'], api_config)
ingestion_service.ingest_api_data('orders', 'api-orders')
```

#### Apache NiFi Flow
```xml
<!-- NiFi Template for API Ingestion -->
<template>
  <description>API to Kafka Pipeline</description>
  <processors>
    <processor>
      <name>InvokeHTTP</name>
      <type>org.apache.nifi.processors.standard.InvokeHTTP</type>
      <properties>
        <property name="HTTP Method">GET</property>
        <property name="Remote URL">https://api.example.com/v1/orders</property>
        <property name="Request Headers">Authorization: Bearer ${api.token}</property>
      </properties>
      <schedulingPeriod>5 min</schedulingPeriod>
    </processor>
    
    <processor>
      <name>SplitJson</name>
      <type>org.apache.nifi.processors.standard.SplitJson</type>
      <properties>
        <property name="JsonPath Expression">$.data[*]</property>
      </properties>
    </processor>
    
    <processor>
      <name>PublishKafka</name>
      <type>org.apache.nifi.processors.kafka.pubsub.PublishKafka_2_6</type>
      <properties>
        <property name="bootstrap.servers">localhost:9092</property>
        <property name="topic">api-orders</property>
        <property name="key">order_id</property>
      </properties>
    </processor>
  </processors>
</template>
```

## Change Data Capture (CDC)

### Industry CDC Patterns

#### 1. Log-Based CDC (Recommended)
```sql
-- PostgreSQL WAL configuration
-- postgresql.conf
wal_level = logical
max_wal_senders = 4
max_replication_slots = 4

-- Create replication slot
SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput');

-- Create publication
CREATE PUBLICATION debezium_publication FOR ALL TABLES;
```

#### 2. Trigger-Based CDC
```sql
-- MySQL trigger-based CDC (Maxwell alternative)
CREATE TABLE maxwell.positions (
    server_id INT UNSIGNED NOT NULL,
    binlog_file VARCHAR(255),
    binlog_position INT UNSIGNED,
    gtid_set VARCHAR(4096),
    client_id VARCHAR(255) NOT NULL DEFAULT 'maxwell',
    heartbeat_at TIMESTAMP NULL,
    PRIMARY KEY (server_id, client_id)
);

-- Audit table for changes
CREATE TABLE audit_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(255),
    operation VARCHAR(10),
    old_values JSON,
    new_values JSON,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trigger example
DELIMITER $$
CREATE TRIGGER orders_audit_insert 
AFTER INSERT ON orders
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, new_values)
    VALUES ('orders', 'INSERT', JSON_OBJECT(
        'order_id', NEW.order_id,
        'customer_id', NEW.customer_id,
        'amount', NEW.amount,
        'created_at', NEW.created_at
    ));
END$$
DELIMITER ;
```

### CDC Best Practices

#### 1. Handling Schema Evolution
```python
# schema_registry_integration.py
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer

class SchemaEvolutionHandler:
    def __init__(self, schema_registry_url):
        self.schema_registry = SchemaRegistryClient({'url': schema_registry_url})
    
    def register_schema(self, subject, schema_str):
        """Register new schema version"""
        try:
            schema_id = self.schema_registry.register_schema(subject, schema_str)
            return schema_id
        except Exception as e:
            print(f"Schema registration failed: {e}")
            return None
    
    def get_latest_schema(self, subject):
        """Get latest schema for backward compatibility"""
        try:
            return self.schema_registry.get_latest_version(subject)
        except Exception as e:
            print(f"Failed to get schema: {e}")
            return None

# Avro schema for orders
orders_schema = """
{
  "type": "record",
  "name": "Order",
  "fields": [
    {"name": "order_id", "type": "long"},
    {"name": "customer_id", "type": "long"},
    {"name": "amount", "type": "double"},
    {"name": "status", "type": "string"},
    {"name": "created_at", "type": "string"},
    {"name": "updated_at", "type": ["null", "string"], "default": null}
  ]
}
"""
```

#### 2. Handling Large Transactions
```yaml
# Debezium configuration for large transactions
connector.config:
  max.batch.size: 2048
  max.queue.size: 8192
  poll.interval.ms: 1000
  
  # Handle large transactions
  transaction.metadata.factory: io.debezium.pipeline.txmetadata.DefaultTransactionMetadataFactory
  provide.transaction.metadata: true
  
  # Snapshot configuration
  snapshot.mode: initial
  snapshot.locking.mode: minimal
  snapshot.fetch.size: 10240
```

## Stream Processing

### Apache Flink Implementation

#### Real-Time Order Processing
```java
// OrderProcessingJob.java
public class OrderProcessingJob {
    
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setStreamTimeCharacteristic(TimeCharacteristic.EventTime);
        
        // Kafka source configuration
        Properties kafkaProps = new Properties();
        kafkaProps.setProperty("bootstrap.servers", "localhost:9092");
        kafkaProps.setProperty("group.id", "order-processing");
        
        // Read from multiple Kafka topics
        DataStream<OrderEvent> orders = env
            .addSource(new FlinkKafkaConsumer<>("orders", new OrderEventSchema(), kafkaProps))
            .assignTimestampsAndWatermarks(
                WatermarkStrategy.<OrderEvent>forBoundedOutOfOrderness(Duration.ofSeconds(20))
                    .withTimestampAssigner((event, timestamp) -> event.getTimestamp())
            );
        
        DataStream<CustomerEvent> customers = env
            .addSource(new FlinkKafkaConsumer<>("customers", new CustomerEventSchema(), kafkaProps));
        
        // Join streams
        DataStream<EnrichedOrder> enrichedOrders = orders
            .keyBy(OrderEvent::getCustomerId)
            .connect(customers.keyBy(CustomerEvent::getCustomerId))
            .process(new OrderCustomerJoinFunction());
        
        // Windowed aggregations
        DataStream<OrderSummary> orderSummaries = enrichedOrders
            .keyBy(order -> order.getCustomerSegment())
            .window(TumblingEventTimeWindows.of(Time.minutes(5)))
            .aggregate(new OrderAggregateFunction());
        
        // Write to HDFS/S3
        orderSummaries
            .addSink(StreamingFileSink
                .forRowFormat(new Path("hdfs://namenode:9000/data/processed/orders"),
                    new SimpleStringEncoder<OrderSummary>("UTF-8"))
                .withRollingPolicy(DefaultRollingPolicy.builder()
                    .withRolloverInterval(TimeUnit.MINUTES.toMillis(15))
                    .withInactivityInterval(TimeUnit.MINUTES.toMillis(5))
                    .build())
                .build());
        
        env.execute("Real-time Order Processing");
    }
}

// Custom join function
public class OrderCustomerJoinFunction extends CoProcessFunction<OrderEvent, CustomerEvent, EnrichedOrder> {
    
    private ValueState<CustomerEvent> customerState;
    
    @Override
    public void open(Configuration parameters) {
        customerState = getRuntimeContext().getState(
            new ValueStateDescriptor<>("customer", CustomerEvent.class));
    }
    
    @Override
    public void processElement1(OrderEvent order, Context ctx, Collector<EnrichedOrder> out) throws Exception {
        CustomerEvent customer = customerState.value();
        if (customer != null) {
            out.collect(new EnrichedOrder(order, customer));
        } else {
            // Register timer to wait for customer data
            ctx.timerService().registerEventTimeTimer(ctx.timestamp() + 60000);
        }
    }
    
    @Override
    public void processElement2(CustomerEvent customer, Context ctx, Collector<EnrichedOrder> out) throws Exception {
        customerState.update(customer);
    }
}
```

#### Spark Structured Streaming
```scala
// SparkStreamingJob.scala
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.streaming.Trigger

object OrderStreamingJob {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("Order Stream Processing")
      .config("spark.sql.streaming.checkpointLocation", "/tmp/checkpoint")
      .getOrCreate()
    
    import spark.implicits._
    
    // Read from Kafka
    val ordersDF = spark
      .readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", "localhost:9092")
      .option("subscribe", "orders")
      .option("startingOffsets", "latest")
      .load()
      .select(
        from_json(col("value").cast("string"), orderSchema).as("order"),
        col("timestamp").as("kafka_timestamp")
      )
      .select("order.*", "kafka_timestamp")
    
    // Real-time aggregations
    val orderAggregates = ordersDF
      .withWatermark("order_timestamp", "10 minutes")
      .groupBy(
        window(col("order_timestamp"), "5 minutes"),
        col("customer_segment")
      )
      .agg(
        sum("amount").as("total_amount"),
        count("*").as("order_count"),
        avg("amount").as("avg_amount")
      )
    
    // Write to multiple sinks
    val query1 = orderAggregates
      .writeStream
      .format("parquet")
      .option("path", "hdfs://namenode:9000/data/aggregates/orders")
      .option("checkpointLocation", "/tmp/checkpoint/aggregates")
      .trigger(Trigger.ProcessingTime("2 minutes"))
      .start()
    
    val query2 = ordersDF
      .writeStream
      .format("delta")
      .option("path", "s3a://data-lake/raw/orders")
      .option("checkpointLocation", "/tmp/checkpoint/raw")
      .trigger(Trigger.ProcessingTime("30 seconds"))
      .start()
    
    query1.awaitTermination()
  }
}
```
## Data Lake Architecture

### Multi-Zone Data Lake Design

#### Zone-Based Architecture
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           RAW ZONE (Bronze)                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ Purpose: Exact copy of source data                                         │
│ Format: Original format (JSON, CSV, Avro, etc.)                           │
│ Schema: Schema-on-read                                                      │
│ Retention: Long-term (years)                                               │
│ Path: /data/raw/{source_system}/{table}/{year}/{month}/{day}              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PROCESSED ZONE (Silver)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ Purpose: Cleaned, validated, deduplicated data                             │
│ Format: Parquet, Delta Lake, Iceberg                                       │
│ Schema: Enforced schema                                                     │
│ Retention: Medium-term (months to years)                                   │
│ Path: /data/processed/{domain}/{table}/{partition_key}                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CURATED ZONE (Gold)                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│ Purpose: Business-ready, aggregated data                                   │
│ Format: Parquet, optimized for analytics                                   │
│ Schema: Star/snowflake schema                                               │
│ Retention: Long-term (years)                                               │
│ Path: /data/curated/{business_domain}/{fact_or_dim_table}                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### HDFS Directory Structure
```bash
# Raw Zone - Partitioned by ingestion date
/data/raw/
├── ecommerce_db/
│   ├── orders/
│   │   ├── year=2023/month=11/day=08/hour=14/
│   │   │   ├── orders_20231108_140000.json
│   │   │   └── orders_20231108_141500.json
│   │   └── year=2023/month=11/day=08/hour=15/
│   ├── customers/
│   └── products/
├── crm_api/
│   ├── leads/
│   └── contacts/
└── web_logs/
    ├── clickstream/
    └── events/

# Processed Zone - Partitioned by business logic
/data/processed/
├── sales/
│   ├── orders/
│   │   ├── order_date=2023-11-08/
│   │   │   └── part-00000-c000.parquet
│   │   └── order_date=2023-11-09/
│   ├── order_items/
│   └── customer_orders/
└── marketing/
    ├── campaigns/
    └── conversions/

# Curated Zone - Dimensional model
/data/curated/
├── sales_mart/
│   ├── fact_sales/
│   │   ├── year=2023/quarter=4/
│   │   │   └── sales_fact.parquet
│   ├── dim_customer/
│   ├── dim_product/
│   └── dim_date/
└── marketing_mart/
    ├── fact_campaigns/
    └── dim_channels/
```

### Storage Format Strategy

#### Apache Iceberg Implementation
```sql
-- Create Iceberg tables in Hive Metastore
CREATE TABLE processed.sales.orders (
    order_id BIGINT,
    customer_id BIGINT,
    product_id BIGINT,
    order_date DATE,
    amount DECIMAL(10,2),
    status STRING,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
) USING ICEBERG
PARTITIONED BY (days(order_date))
TBLPROPERTIES (
    'write.format.default' = 'parquet',
    'write.parquet.compression-codec' = 'zstd',
    'write.target-file-size-bytes' = '134217728'  -- 128MB
);

-- Schema evolution example
ALTER TABLE processed.sales.orders 
ADD COLUMN shipping_address STRUCT<
    street: STRING,
    city: STRING,
    state: STRING,
    zip: STRING
>;
```

#### Delta Lake Alternative
```scala
// Delta Lake table creation
import io.delta.tables._
import org.apache.spark.sql.types._

val orderSchema = StructType(Array(
  StructField("order_id", LongType, false),
  StructField("customer_id", LongType, false),
  StructField("product_id", LongType, false),
  StructField("order_date", DateType, false),
  StructField("amount", DecimalType(10,2), false),
  StructField("status", StringType, false),
  StructField("created_at", TimestampType, false),
  StructField("updated_at", TimestampType, true)
))

// Create Delta table
DeltaTable.create(spark)
  .tableName("processed.sales.orders")
  .addColumns(orderSchema)
  .partitionedBy("order_date")
  .property("delta.autoOptimize.optimizeWrite", "true")
  .property("delta.autoOptimize.autoCompact", "true")
  .execute()
```

## ETL/ELT Patterns

### Apache Airflow Orchestration

#### DAG for Daily ETL Pipeline
```python
# daily_etl_dag.py
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash_operator import BashOperator
from airflow.operators.python_operator import PythonOperator
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator

default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'start_date': datetime(2023, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5)
}

dag = DAG(
    'daily_etl_pipeline',
    default_args=default_args,
    description='Daily ETL pipeline for sales data',
    schedule_interval='0 2 * * *',  # Run at 2 AM daily
    catchup=False,
    max_active_runs=1
)

# Data quality checks
def check_data_quality(**context):
    """Validate data quality before processing"""
    execution_date = context['execution_date']
    
    # Check record counts
    expected_min_records = 1000
    actual_records = get_record_count(execution_date)
    
    if actual_records < expected_min_records:
        raise ValueError(f"Data quality check failed: {actual_records} < {expected_min_records}")
    
    # Check for duplicates
    duplicate_count = check_duplicates(execution_date)
    if duplicate_count > 0:
        raise ValueError(f"Found {duplicate_count} duplicate records")
    
    return "Data quality checks passed"

# Extract from PostgreSQL
extract_orders = BashOperator(
    task_id='extract_orders',
    bash_command="""
    sqoop import \
      --connect jdbc:postgresql://postgres:5432/ecommerce \
      --username {{ var.value.db_user }} \
      --password {{ var.value.db_password }} \
      --table orders \
      --target-dir /data/raw/ecommerce/orders/{{ ds }} \
      --where "created_at >= '{{ ds }}' AND created_at < '{{ next_ds }}'" \
      --file-format parquet \
      --compression-codec snappy
    """,
    dag=dag
)

# Data quality validation
validate_data = PythonOperator(
    task_id='validate_data_quality',
    python_callable=check_data_quality,
    dag=dag
)

# Transform with Spark
transform_orders = SparkSubmitOperator(
    task_id='transform_orders',
    application='/opt/spark/jobs/transform_orders.py',
    application_args=[
        '--input-path', '/data/raw/ecommerce/orders/{{ ds }}',
        '--output-path', '/data/processed/sales/orders',
        '--partition-date', '{{ ds }}'
    ],
    conf={
        'spark.sql.adaptive.enabled': 'true',
        'spark.sql.adaptive.coalescePartitions.enabled': 'true',
        'spark.serializer': 'org.apache.spark.serializer.KryoSerializer'
    },
    dag=dag
)

# Load to Hive
load_to_hive = PostgresOperator(
    task_id='load_to_hive',
    postgres_conn_id='hive_metastore',
    sql="""
    MSCK REPAIR TABLE processed.sales.orders;
    
    INSERT OVERWRITE TABLE curated.sales_mart.fact_sales
    PARTITION (order_date = '{{ ds }}')
    SELECT 
        o.order_id,
        c.customer_key,
        p.product_key,
        d.date_key,
        o.amount,
        o.quantity,
        o.discount_amount
    FROM processed.sales.orders o
    JOIN curated.sales_mart.dim_customer c ON o.customer_id = c.customer_id
    JOIN curated.sales_mart.dim_product p ON o.product_id = p.product_id  
    JOIN curated.sales_mart.dim_date d ON o.order_date = d.date_value
    WHERE o.order_date = '{{ ds }}';
    """,
    dag=dag
)

# Data lineage tracking
track_lineage = PythonOperator(
    task_id='track_data_lineage',
    python_callable=lambda **context: track_data_lineage(
        source_table='ecommerce.orders',
        target_table='curated.sales_mart.fact_sales',
        execution_date=context['execution_date'],
        record_count=context['task_instance'].xcom_pull(task_ids='validate_data_quality')
    ),
    dag=dag
)

# Task dependencies
extract_orders >> validate_data >> transform_orders >> load_to_hive >> track_lineage
```

#### Spark ETL Job
```python
# transform_orders.py
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
import argparse

def create_spark_session():
    return SparkSession.builder \
        .appName("Transform Orders") \
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
        .config("spark.sql.catalog.spark_catalog", "org.apache.iceberg.spark.SparkSessionCatalog") \
        .config("spark.sql.catalog.spark_catalog.type", "hive") \
        .getOrCreate()

def transform_orders(spark, input_path, output_path, partition_date):
    """Transform raw orders data"""
    
    # Read raw data
    raw_orders = spark.read.parquet(input_path)
    
    # Data cleaning and transformation
    cleaned_orders = raw_orders \
        .filter(col("amount") > 0) \
        .filter(col("customer_id").isNotNull()) \
        .withColumn("order_date", to_date(col("created_at"))) \
        .withColumn("order_hour", hour(col("created_at"))) \
        .withColumn("amount_usd", 
                   when(col("currency") == "EUR", col("amount") * 1.1)
                   .when(col("currency") == "GBP", col("amount") * 1.25)
                   .otherwise(col("amount"))) \
        .withColumn("customer_segment",
                   when(col("amount_usd") > 1000, "Premium")
                   .when(col("amount_usd") > 100, "Standard")
                   .otherwise("Basic")) \
        .drop("currency")
    
    # Data validation
    record_count = cleaned_orders.count()
    null_count = cleaned_orders.filter(col("customer_id").isNull()).count()
    
    if null_count > 0:
        raise ValueError(f"Found {null_count} records with null customer_id")
    
    # Write to processed zone
    cleaned_orders.write \
        .mode("overwrite") \
        .partitionBy("order_date") \
        .option("path", f"{output_path}/order_date={partition_date}") \
        .parquet(f"{output_path}/order_date={partition_date}")
    
    # Update Iceberg table
    cleaned_orders.writeTo("processed.sales.orders") \
        .append()
    
    return record_count

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-path", required=True)
    parser.add_argument("--output-path", required=True)
    parser.add_argument("--partition-date", required=True)
    args = parser.parse_args()
    
    spark = create_spark_session()
    
    try:
        record_count = transform_orders(
            spark, 
            args.input_path, 
            args.output_path, 
            args.partition_date
        )
        print(f"Successfully processed {record_count} records")
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
```

### Real-Time ELT with Kafka Streams

#### Kafka Streams Processing
```java
// OrderStreamProcessor.java
public class OrderStreamProcessor {
    
    public static void main(String[] args) {
        Properties props = new Properties();
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, "order-stream-processor");
        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:9092");
        props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
        props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass());
        
        StreamsBuilder builder = new StreamsBuilder();
        
        // Input streams
        KStream<String, String> orders = builder.stream("orders");
        KTable<String, String> customers = builder.table("customers");
        KTable<String, String> products = builder.table("products");
        
        // Parse JSON and enrich
        KStream<String, OrderEnriched> enrichedOrders = orders
            .mapValues(OrderStreamProcessor::parseOrder)
            .selectKey((key, order) -> order.getCustomerId())
            .join(customers, 
                (order, customer) -> enrichWithCustomer(order, customer),
                Joined.with(Serdes.String(), orderSerde, Serdes.String()))
            .selectKey((key, order) -> order.getProductId())
            .join(products,
                (order, product) -> enrichWithProduct(order, product),
                Joined.with(Serdes.String(), orderEnrichedSerde, Serdes.String()));
        
        // Real-time aggregations
        KTable<Windowed<String>, Long> orderCounts = enrichedOrders
            .groupBy((key, order) -> order.getCustomerSegment())
            .windowedBy(TimeWindows.of(Duration.ofMinutes(5)))
            .count();
        
        KTable<Windowed<String>, Double> revenueBySegment = enrichedOrders
            .groupBy((key, order) -> order.getCustomerSegment())
            .windowedBy(TimeWindows.of(Duration.ofMinutes(5)))
            .aggregate(
                () -> 0.0,
                (key, order, aggregate) -> aggregate + order.getAmount(),
                Materialized.with(Serdes.String(), Serdes.Double())
            );
        
        // Output to different topics
        enrichedOrders.to("orders-enriched", Produced.with(Serdes.String(), orderEnrichedSerde));
        
        orderCounts
            .toStream()
            .map((windowedKey, count) -> KeyValue.pair(
                windowedKey.key() + "@" + windowedKey.window().start(),
                count.toString()
            ))
            .to("order-counts-by-segment");
        
        // Build and start
        KafkaStreams streams = new KafkaStreams(builder.build(), props);
        streams.start();
        
        // Graceful shutdown
        Runtime.getRuntime().addShutdownHook(new Thread(streams::close));
    }
    
    private static Order parseOrder(String orderJson) {
        // JSON parsing logic
        return JsonUtils.parseOrder(orderJson);
    }
    
    private static OrderEnriched enrichWithCustomer(Order order, String customerJson) {
        Customer customer = JsonUtils.parseCustomer(customerJson);
        return new OrderEnriched(order, customer, null);
    }
    
    private static OrderEnriched enrichWithProduct(OrderEnriched order, String productJson) {
        Product product = JsonUtils.parseProduct(productJson);
        return order.withProduct(product);
    }
}
```

## Data Quality & Governance

### Data Quality Framework

#### Great Expectations Integration
```python
# data_quality_suite.py
import great_expectations as ge
from great_expectations.dataset import SparkDFDataset

class DataQualityValidator:
    def __init__(self, spark_session):
        self.spark = spark_session
        self.context = ge.get_context()
    
    def validate_orders_data(self, df_path, execution_date):
        """Comprehensive data quality validation for orders"""
        
        # Load data as Great Expectations dataset
        df = self.spark.read.parquet(df_path)
        ge_df = SparkDFDataset(df)
        
        # Define expectations
        expectations = [
            # Completeness checks
            ge_df.expect_column_to_not_be_null("order_id"),
            ge_df.expect_column_to_not_be_null("customer_id"),
            ge_df.expect_column_to_not_be_null("amount"),
            
            # Validity checks
            ge_df.expect_column_values_to_be_of_type("order_id", "LongType"),
            ge_df.expect_column_values_to_be_between("amount", 0, 100000),
            ge_df.expect_column_values_to_be_in_set("status", 
                ["pending", "confirmed", "shipped", "delivered", "cancelled"]),
            
            # Uniqueness checks
            ge_df.expect_column_values_to_be_unique("order_id"),
            
            # Consistency checks
            ge_df.expect_column_pair_values_A_to_be_greater_than_B(
                "updated_at", "created_at"),
            
            # Business rule checks
            ge_df.expect_column_values_to_match_regex("email", 
                r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"),
            
            # Statistical checks
            ge_df.expect_column_mean_to_be_between("amount", 10, 1000),
            ge_df.expect_column_quantile_values_to_be_between("amount", 
                quantile_ranges={"quantiles": [0.05, 0.95], "value_ranges": [[1, 50], [100, 5000]]}),
        ]
        
        # Run validation
        validation_results = []
        for expectation in expectations:
            result = expectation.validate()
            validation_results.append(result)
            
            if not result.success:
                print(f"Data quality check failed: {result}")
        
        # Generate data quality report
        self.generate_dq_report(validation_results, execution_date)
        
        return all(result.success for result in validation_results)
    
    def generate_dq_report(self, results, execution_date):
        """Generate data quality report"""
        report = {
            "execution_date": execution_date,
            "total_checks": len(results),
            "passed_checks": sum(1 for r in results if r.success),
            "failed_checks": sum(1 for r in results if not r.success),
            "success_rate": sum(1 for r in results if r.success) / len(results),
            "details": [
                {
                    "expectation": r.expectation_config.expectation_type,
                    "success": r.success,
                    "result": r.result
                } for r in results
            ]
        }
        
        # Store report in monitoring system
        self.store_dq_report(report)
```

#### Apache Griffin Data Quality
```yaml
# griffin-dq-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: griffin-measures
data:
  accuracy-measure.json: |
    {
      "name": "order_accuracy_measure",
      "measure.type": "accuracy",
      "data.sources": [
        {
          "name": "source",
          "connectors": [
            {
              "type": "hive",
              "config": {
                "database": "raw",
                "table.name": "orders"
              }
            }
          ]
        },
        {
          "name": "target", 
          "connectors": [
            {
              "type": "hive",
              "config": {
                "database": "processed",
                "table.name": "orders"
              }
            }
          ]
        }
      ],
      "evaluate.rule": {
        "rules": [
          {
            "dsl.type": "griffin-dsl",
            "dq.type": "accuracy",
            "rule": "source.order_id = target.order_id AND source.amount = target.amount",
            "details": {
              "source": "source",
              "target": "target",
              "miss": "count(source.order_id) - count(target.order_id)",
              "total": "count(source.order_id)",
              "matched": "count(target.order_id)"
            }
          }
        ]
      }
    }
```

### Data Lineage Tracking

#### Apache Atlas Integration
```python
# data_lineage_tracker.py
from pyatlasclient.client import Atlas
import json

class DataLineageTracker:
    def __init__(self, atlas_url, username, password):
        self.atlas = Atlas(atlas_url, username=username, password=password)
    
    def create_dataset_entity(self, dataset_info):
        """Create dataset entity in Atlas"""
        entity = {
            "typeName": "DataSet",
            "attributes": {
                "name": dataset_info["name"],
                "qualifiedName": dataset_info["qualified_name"],
                "description": dataset_info.get("description", ""),
                "owner": dataset_info.get("owner", "data-engineering"),
                "format": dataset_info.get("format", "parquet"),
                "location": dataset_info["location"],
                "schema": json.dumps(dataset_info.get("schema", {}))
            }
        }
        
        return self.atlas.entity_post.create(entity=entity)
    
    def create_process_entity(self, process_info):
        """Create ETL process entity"""
        entity = {
            "typeName": "Process",
            "attributes": {
                "name": process_info["name"],
                "qualifiedName": process_info["qualified_name"],
                "description": process_info.get("description", ""),
                "owner": process_info.get("owner", "data-engineering"),
                "inputs": [{"guid": guid} for guid in process_info["input_guids"]],
                "outputs": [{"guid": guid} for guid in process_info["output_guids"]]
            }
        }
        
        return self.atlas.entity_post.create(entity=entity)
    
    def track_airflow_dag_lineage(self, dag_id, task_id, inputs, outputs):
        """Track lineage for Airflow DAG execution"""
        
        # Create input dataset entities
        input_guids = []
        for input_dataset in inputs:
            entity = self.create_dataset_entity(input_dataset)
            input_guids.append(entity["guid"])
        
        # Create output dataset entities  
        output_guids = []
        for output_dataset in outputs:
            entity = self.create_dataset_entity(output_dataset)
            output_guids.append(entity["guid"])
        
        # Create process entity
        process_info = {
            "name": f"{dag_id}_{task_id}",
            "qualified_name": f"airflow://{dag_id}/{task_id}",
            "description": f"Airflow task {task_id} in DAG {dag_id}",
            "input_guids": input_guids,
            "output_guids": output_guids
        }
        
        return self.create_process_entity(process_info)

# Usage in Airflow DAG
def track_lineage_callback(context):
    """Airflow callback to track data lineage"""
    lineage_tracker = DataLineageTracker(
        atlas_url="http://atlas:21000",
        username="admin", 
        password="admin"
    )
    
    # Define inputs and outputs for this task
    inputs = [
        {
            "name": "ecommerce_orders",
            "qualified_name": "postgresql://ecommerce/orders",
            "location": "postgresql://postgres:5432/ecommerce/orders",
            "format": "postgresql_table"
        }
    ]
    
    outputs = [
        {
            "name": "processed_orders", 
            "qualified_name": "hdfs://processed/sales/orders",
            "location": "hdfs://namenode:9000/data/processed/sales/orders",
            "format": "parquet"
        }
    ]
    
    lineage_tracker.track_airflow_dag_lineage(
        context['dag'].dag_id,
        context['task'].task_id,
        inputs,
        outputs
    )
```
## Monitoring & Operations

### Infrastructure Monitoring

#### Prometheus + Grafana Stack
```yaml
# docker-compose-monitoring.yml
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./grafana/datasources:/etc/grafana/provisioning/datasources

  node-exporter:
    image: prom/node-exporter:latest
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'

  kafka-exporter:
    image: danielqsj/kafka-exporter:latest
    ports:
      - "9308:9308"
    command:
      - '--kafka.server=kafka:9092'

volumes:
  prometheus_data:
  grafana_data:
```

#### Prometheus Configuration
```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Hadoop/HDFS monitoring
  - job_name: 'hdfs-namenode'
    static_configs:
      - targets: ['namenode:9870']
    metrics_path: /jmx
    params:
      qry: ['Hadoop:service=NameNode,name=*']

  - job_name: 'hdfs-datanode'
    static_configs:
      - targets: ['datanode1:9864', 'datanode2:9864', 'datanode3:9864']

  # Kafka monitoring
  - job_name: 'kafka'
    static_configs:
      - targets: ['kafka1:9092', 'kafka2:9092', 'kafka3:9092']

  # Spark monitoring
  - job_name: 'spark-master'
    static_configs:
      - targets: ['spark-master:8080']

  - job_name: 'spark-workers'
    static_configs:
      - targets: ['spark-worker1:8081', 'spark-worker2:8081']

  # Flink monitoring
  - job_name: 'flink-jobmanager'
    static_configs:
      - targets: ['flink-jobmanager:8081']

  # Custom application metrics
  - job_name: 'data-pipeline-metrics'
    static_configs:
      - targets: ['pipeline-monitor:8080']
```

#### Custom Pipeline Metrics
```python
# pipeline_metrics.py
from prometheus_client import Counter, Histogram, Gauge, start_http_server
import time
import threading

class PipelineMetrics:
    def __init__(self):
        # Counters
        self.records_processed = Counter(
            'pipeline_records_processed_total',
            'Total number of records processed',
            ['source', 'destination', 'pipeline']
        )
        
        self.pipeline_errors = Counter(
            'pipeline_errors_total',
            'Total number of pipeline errors',
            ['pipeline', 'error_type']
        )
        
        # Histograms
        self.processing_duration = Histogram(
            'pipeline_processing_duration_seconds',
            'Time spent processing batches',
            ['pipeline', 'stage']
        )
        
        self.batch_size = Histogram(
            'pipeline_batch_size',
            'Size of processed batches',
            ['pipeline', 'source']
        )
        
        # Gauges
        self.active_pipelines = Gauge(
            'pipeline_active_count',
            'Number of currently active pipelines'
        )
        
        self.data_lag = Gauge(
            'pipeline_data_lag_seconds',
            'Data processing lag in seconds',
            ['pipeline', 'source']
        )
        
        self.queue_depth = Gauge(
            'pipeline_queue_depth',
            'Number of messages in processing queue',
            ['queue_name']
        )
    
    def record_batch_processed(self, source, destination, pipeline, count, duration):
        """Record metrics for a processed batch"""
        self.records_processed.labels(
            source=source, 
            destination=destination, 
            pipeline=pipeline
        ).inc(count)
        
        self.processing_duration.labels(
            pipeline=pipeline, 
            stage='batch_processing'
        ).observe(duration)
        
        self.batch_size.labels(
            pipeline=pipeline, 
            source=source
        ).observe(count)
    
    def record_error(self, pipeline, error_type):
        """Record pipeline error"""
        self.pipeline_errors.labels(
            pipeline=pipeline, 
            error_type=error_type
        ).inc()
    
    def update_data_lag(self, pipeline, source, lag_seconds):
        """Update data processing lag"""
        self.data_lag.labels(
            pipeline=pipeline, 
            source=source
        ).set(lag_seconds)
    
    def update_queue_depth(self, queue_name, depth):
        """Update queue depth"""
        self.queue_depth.labels(queue_name=queue_name).set(depth)

# Usage in pipeline code
metrics = PipelineMetrics()

def process_kafka_batch(consumer, producer):
    """Example pipeline with metrics"""
    start_time = time.time()
    
    try:
        # Consume batch
        messages = consumer.poll(timeout_ms=1000)
        batch_size = len(messages)
        
        if batch_size > 0:
            # Process messages
            processed_records = []
            for message in messages:
                processed_record = transform_record(message.value)
                processed_records.append(processed_record)
            
            # Produce to output topic
            for record in processed_records:
                producer.send('processed-orders', record)
            
            # Record metrics
            duration = time.time() - start_time
            metrics.record_batch_processed(
                source='kafka-orders',
                destination='processed-orders', 
                pipeline='order-processing',
                count=batch_size,
                duration=duration
            )
            
            # Calculate and update lag
            latest_offset = consumer.end_offsets(consumer.assignment())[0]
            current_offset = consumer.position(consumer.assignment()[0])
            lag = latest_offset - current_offset
            metrics.update_data_lag('order-processing', 'kafka-orders', lag)
            
    except Exception as e:
        metrics.record_error('order-processing', type(e).__name__)
        raise

# Start metrics server
if __name__ == '__main__':
    start_http_server(8080)
    print("Metrics server started on port 8080")
```

### Alerting Rules
```yaml
# alert_rules.yml
groups:
- name: data_pipeline_alerts
  rules:
  # High error rate
  - alert: HighPipelineErrorRate
    expr: rate(pipeline_errors_total[5m]) > 0.1
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High error rate in data pipeline"
      description: "Pipeline {{ $labels.pipeline }} has error rate of {{ $value }} errors/sec"

  # Data processing lag
  - alert: HighDataLag
    expr: pipeline_data_lag_seconds > 3600
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "High data processing lag"
      description: "Pipeline {{ $labels.pipeline }} has {{ $value }} seconds of lag"

  # HDFS capacity
  - alert: HDFSHighCapacity
    expr: (hdfs_capacity_used / hdfs_capacity_total) > 0.85
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "HDFS capacity is high"
      description: "HDFS is {{ $value | humanizePercentage }} full"

  # Kafka consumer lag
  - alert: KafkaConsumerLag
    expr: kafka_consumer_lag_sum > 100000
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Kafka consumer lag is high"
      description: "Consumer group {{ $labels.consumergroup }} has lag of {{ $value }} messages"
```

## Real-World Case Studies

### Case Study 1: E-commerce Company (Netflix-style Architecture)

#### Business Requirements
- **Data Sources**: PostgreSQL (orders, customers), MySQL (inventory), Kafka (clickstream), REST APIs (payments)
- **Volume**: 10M orders/day, 100M clickstream events/day
- **Latency**: Real-time fraud detection, near real-time recommendations
- **Analytics**: Daily/hourly reports, ML feature store

#### Architecture Implementation
```yaml
# Netflix-inspired data platform
Data Sources:
  - PostgreSQL (OLTP): Orders, Customers, Products
  - MySQL (Inventory): Stock levels, warehouses
  - Kafka (Events): Clickstream, user interactions
  - APIs: Payment gateway, shipping providers

Ingestion Layer:
  - Debezium: CDC from PostgreSQL/MySQL
  - Kafka Connect: API polling connectors
  - Custom producers: Real-time event streaming

Stream Processing:
  - Flink: Real-time fraud detection, session analysis
  - Kafka Streams: User behavior aggregation
  - Spark Streaming: Feature engineering for ML

Storage:
  - HDFS: Raw data lake (Bronze layer)
  - Iceberg: Processed analytics tables (Silver/Gold)
  - Elasticsearch: Real-time search and analytics
  - Cassandra: User profiles and recommendations

Analytics:
  - Trino: Interactive analytics and reporting
  - Spark: Batch ML training and feature engineering
  - Jupyter: Data science and exploration
```

#### Implementation Details
```python
# Real-time fraud detection with Flink
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment

def fraud_detection_pipeline():
    env = StreamExecutionEnvironment.get_execution_environment()
    t_env = StreamTableEnvironment.create(env)
    
    # Define source tables
    t_env.execute_sql("""
        CREATE TABLE orders (
            order_id BIGINT,
            customer_id BIGINT,
            amount DECIMAL(10,2),
            payment_method STRING,
            merchant_id BIGINT,
            order_time TIMESTAMP(3),
            WATERMARK FOR order_time AS order_time - INTERVAL '5' SECOND
        ) WITH (
            'connector' = 'kafka',
            'topic' = 'orders',
            'properties.bootstrap.servers' = 'kafka:9092',
            'format' = 'json'
        )
    """)
    
    # Fraud detection rules
    fraud_alerts = t_env.sql_query("""
        SELECT 
            customer_id,
            COUNT(*) as order_count,
            SUM(amount) as total_amount,
            TUMBLE_START(order_time, INTERVAL '5' MINUTE) as window_start
        FROM orders
        GROUP BY 
            customer_id,
            TUMBLE(order_time, INTERVAL '5' MINUTE)
        HAVING 
            COUNT(*) > 10 OR SUM(amount) > 10000
    """)
    
    # Output to alert topic
    t_env.execute_sql("""
        CREATE TABLE fraud_alerts (
            customer_id BIGINT,
            order_count BIGINT,
            total_amount DECIMAL(10,2),
            window_start TIMESTAMP(3)
        ) WITH (
            'connector' = 'kafka',
            'topic' = 'fraud-alerts',
            'properties.bootstrap.servers' = 'kafka:9092',
            'format' = 'json'
        )
    """)
    
    fraud_alerts.execute_insert("fraud_alerts")

# Feature store implementation
class FeatureStore:
    def __init__(self, spark_session):
        self.spark = spark_session
    
    def create_customer_features(self):
        """Create customer behavior features"""
        
        # Historical order features
        order_features = self.spark.sql("""
            SELECT 
                customer_id,
                COUNT(*) as total_orders,
                SUM(amount) as total_spent,
                AVG(amount) as avg_order_value,
                MAX(order_date) as last_order_date,
                DATEDIFF(CURRENT_DATE(), MAX(order_date)) as days_since_last_order,
                COUNT(DISTINCT product_category) as categories_purchased
            FROM processed.sales.orders
            WHERE order_date >= DATE_SUB(CURRENT_DATE(), 365)
            GROUP BY customer_id
        """)
        
        # Clickstream features
        clickstream_features = self.spark.sql("""
            SELECT 
                customer_id,
                COUNT(*) as total_sessions,
                SUM(session_duration) as total_session_time,
                AVG(session_duration) as avg_session_duration,
                COUNT(DISTINCT page_category) as pages_visited
            FROM processed.web.sessions
            WHERE session_date >= DATE_SUB(CURRENT_DATE(), 30)
            GROUP BY customer_id
        """)
        
        # Join features
        customer_features = order_features.join(
            clickstream_features, 
            on="customer_id", 
            how="left"
        ).fillna(0)
        
        # Write to feature store
        customer_features.write \
            .mode("overwrite") \
            .option("path", "hdfs://namenode:9000/feature-store/customer-features") \
            .saveAsTable("feature_store.customer_features")
        
        return customer_features
```

### Case Study 2: Financial Services (Goldman Sachs-style)

#### Business Requirements
- **Regulatory Compliance**: Audit trails, data lineage, retention policies
- **Risk Management**: Real-time position monitoring, stress testing
- **Data Quality**: 99.9% accuracy, comprehensive validation
- **Security**: Encryption at rest/transit, access controls

#### Architecture Implementation
```yaml
Compliance-First Architecture:

Data Governance:
  - Apache Atlas: Metadata management and lineage
  - Apache Ranger: Fine-grained access control
  - Immutable audit logs: All data changes tracked

Security:
  - Kerberos: Authentication across all services
  - TLS: Encryption in transit
  - HDFS Encryption Zones: Encryption at rest
  - Vault: Secret management

Data Quality:
  - Great Expectations: Automated data validation
  - Apache Griffin: Data quality monitoring
  - Custom validation: Business rule enforcement

Processing:
  - Spark: Batch processing with checkpointing
  - Flink: Exactly-once processing guarantees
  - Airflow: Workflow orchestration with SLA monitoring
```

#### Implementation Example
```python
# Regulatory compliance pipeline
class ComplianceDataPipeline:
    def __init__(self):
        self.audit_logger = AuditLogger()
        self.data_classifier = DataClassifier()
        self.encryption_service = EncryptionService()
    
    def process_trading_data(self, trading_records):
        """Process trading data with full compliance"""
        
        # Audit data ingestion
        self.audit_logger.log_data_access(
            user=get_current_user(),
            data_source="trading_system",
            access_type="read",
            record_count=len(trading_records),
            timestamp=datetime.utcnow()
        )
        
        # Classify sensitive data
        classified_records = []
        for record in trading_records:
            classification = self.data_classifier.classify(record)
            
            # Encrypt PII fields
            if classification.contains_pii:
                record = self.encryption_service.encrypt_pii_fields(record)
            
            # Add classification metadata
            record['data_classification'] = classification.level
            record['retention_period'] = classification.retention_days
            
            classified_records.append(record)
        
        # Data quality validation
        validation_results = self.validate_trading_data(classified_records)
        if not validation_results.all_passed:
            raise DataQualityException(
                f"Data quality validation failed: {validation_results.failures}"
            )
        
        # Store with audit trail
        self.store_with_lineage(classified_records, "processed.trading.positions")
        
        return classified_records
    
    def validate_trading_data(self, records):
        """Comprehensive data validation"""
        
        df = pd.DataFrame(records)
        
        # Business rule validations
        validations = [
            # Position limits
            df['position_value'].abs() <= df['position_limit'],
            
            # Trade settlement dates
            df['settlement_date'] >= df['trade_date'],
            
            # Currency codes
            df['currency'].isin(['USD', 'EUR', 'GBP', 'JPY']),
            
            # Counterparty validation
            df['counterparty_id'].notna(),
            
            # Price reasonableness
            (df['price'] > 0) & (df['price'] < df['price'].quantile(0.99) * 2)
        ]
        
        results = ValidationResults()
        for i, validation in enumerate(validations):
            if not validation.all():
                results.add_failure(f"Validation {i} failed for {(~validation).sum()} records")
        
        return results

# Automated compliance reporting
class ComplianceReporter:
    def generate_daily_report(self, report_date):
        """Generate daily compliance report"""
        
        report = {
            "report_date": report_date,
            "data_quality_metrics": self.get_dq_metrics(report_date),
            "processing_statistics": self.get_processing_stats(report_date),
            "security_events": self.get_security_events(report_date),
            "lineage_completeness": self.check_lineage_completeness(report_date)
        }
        
        # Store report in immutable storage
        self.store_compliance_report(report)
        
        # Send alerts for any issues
        if report["data_quality_metrics"]["success_rate"] < 0.999:
            self.send_alert("Data quality below threshold", report)
        
        return report
```

### Case Study 3: Manufacturing IoT (Siemens-style)

#### Business Requirements
- **IoT Data**: 1M+ sensors, 1TB/day time-series data
- **Predictive Maintenance**: Real-time anomaly detection
- **Edge Processing**: Local processing at factory sites
- **Batch Analytics**: Equipment efficiency, quality analysis

#### Architecture Implementation
```yaml
Edge-to-Cloud Architecture:

Edge Layer (Factory):
  - Apache NiFi: Local data collection and preprocessing
  - InfluxDB: Time-series data storage
  - Edge Spark: Local anomaly detection
  - MQTT: Sensor data ingestion

Cloud Layer (Data Center):
  - Kafka: Central event streaming
  - Flink: Real-time stream processing
  - HDFS + Iceberg: Long-term analytics storage
  - TimescaleDB: Time-series analytics

Analytics:
  - Spark MLlib: Predictive maintenance models
  - Grafana: Real-time dashboards
  - Jupyter: Data science and model development
```

#### Implementation Example
```python
# IoT data processing pipeline
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.common.typeinfo import Types
from pyflink.datastream.connectors import FlinkKafkaConsumer

class IoTDataProcessor:
    def __init__(self):
        self.env = StreamExecutionEnvironment.get_execution_environment()
        self.env.set_parallelism(4)
    
    def create_anomaly_detection_pipeline(self):
        """Real-time anomaly detection for manufacturing equipment"""
        
        # Kafka source for sensor data
        kafka_consumer = FlinkKafkaConsumer(
            topics=['sensor-data'],
            deserialization_schema=JsonRowDeserializationSchema.builder()
                .type_info(Types.ROW([
                    Types.STRING(),  # sensor_id
                    Types.DOUBLE(),  # temperature
                    Types.DOUBLE(),  # vibration
                    Types.DOUBLE(),  # pressure
                    Types.LONG()     # timestamp
                ]))
                .build(),
            properties={'bootstrap.servers': 'kafka:9092'}
        )
        
        sensor_stream = self.env.add_source(kafka_consumer)
        
        # Sliding window for anomaly detection
        anomaly_stream = sensor_stream \
            .key_by(lambda x: x[0]) \
            .window(SlidingEventTimeWindows.of(
                Time.minutes(10), 
                Time.minutes(1)
            )) \
            .apply(AnomalyDetectionFunction())
        
        # Alert sink
        anomaly_stream.add_sink(
            FlinkKafkaProducer(
                topic='equipment-alerts',
                serialization_schema=JsonRowSerializationSchema.builder()
                    .with_type_info(Types.ROW([
                        Types.STRING(),  # equipment_id
                        Types.STRING(),  # anomaly_type
                        Types.DOUBLE(),  # severity_score
                        Types.LONG()     # detection_time
                    ]))
                    .build(),
                producer_config={'bootstrap.servers': 'kafka:9092'}
            )
        )
        
        return self.env.execute("IoT Anomaly Detection")

class AnomalyDetectionFunction(WindowFunction):
    """Statistical anomaly detection using z-score"""
    
    def apply(self, key, window, inputs, collector):
        values = list(inputs)
        
        if len(values) < 10:  # Need minimum samples
            return
        
        # Extract metrics
        temperatures = [v[1] for v in values]
        vibrations = [v[2] for v in values]
        pressures = [v[3] for v in values]
        
        # Calculate z-scores
        temp_zscore = self.calculate_zscore(temperatures)
        vib_zscore = self.calculate_zscore(vibrations)
        pressure_zscore = self.calculate_zscore(pressures)
        
        # Detect anomalies (z-score > 3)
        if abs(temp_zscore) > 3:
            collector.collect((key, "temperature_anomaly", abs(temp_zscore), window.max_timestamp()))
        
        if abs(vib_zscore) > 3:
            collector.collect((key, "vibration_anomaly", abs(vib_zscore), window.max_timestamp()))
        
        if abs(pressure_zscore) > 3:
            collector.collect((key, "pressure_anomaly", abs(pressure_zscore), window.max_timestamp()))
    
    def calculate_zscore(self, values):
        mean = sum(values) / len(values)
        variance = sum((x - mean) ** 2 for x in values) / len(values)
        std_dev = variance ** 0.5
        
        if std_dev == 0:
            return 0
        
        latest_value = values[-1]
        return (latest_value - mean) / std_dev

# Predictive maintenance model training
class PredictiveMaintenanceML:
    def __init__(self, spark_session):
        self.spark = spark_session
    
    def train_failure_prediction_model(self):
        """Train model to predict equipment failures"""
        
        # Load historical sensor data with failure labels
        training_data = self.spark.sql("""
            SELECT 
                equipment_id,
                -- Time-based features
                hour(timestamp) as hour_of_day,
                dayofweek(timestamp) as day_of_week,
                
                -- Sensor features
                avg(temperature) as avg_temperature,
                stddev(temperature) as std_temperature,
                max(temperature) as max_temperature,
                
                avg(vibration) as avg_vibration,
                stddev(vibration) as std_vibration,
                max(vibration) as max_vibration,
                
                avg(pressure) as avg_pressure,
                stddev(pressure) as std_pressure,
                
                -- Rolling statistics
                avg(temperature) OVER (
                    PARTITION BY equipment_id 
                    ORDER BY timestamp 
                    ROWS BETWEEN 100 PRECEDING AND CURRENT ROW
                ) as rolling_avg_temp,
                
                -- Target variable (failure within next 24 hours)
                CASE WHEN 
                    lead(failure_timestamp, 1) OVER (
                        PARTITION BY equipment_id 
                        ORDER BY timestamp
                    ) - timestamp <= 86400 
                THEN 1 ELSE 0 END as failure_within_24h
                
            FROM processed.iot.sensor_readings s
            LEFT JOIN processed.maintenance.failures f 
                ON s.equipment_id = f.equipment_id
                AND f.failure_timestamp BETWEEN s.timestamp AND s.timestamp + 86400
            WHERE s.timestamp >= DATE_SUB(CURRENT_DATE(), 365)
            GROUP BY equipment_id, date_trunc('hour', timestamp)
        """)
        
        # Feature engineering
        from pyspark.ml.feature import VectorAssembler, StandardScaler
        from pyspark.ml.classification import RandomForestClassifier
        from pyspark.ml import Pipeline
        
        feature_cols = [
            'hour_of_day', 'day_of_week',
            'avg_temperature', 'std_temperature', 'max_temperature',
            'avg_vibration', 'std_vibration', 'max_vibration',
            'avg_pressure', 'std_pressure', 'rolling_avg_temp'
        ]
        
        assembler = VectorAssembler(
            inputCols=feature_cols,
            outputCol="raw_features"
        )
        
        scaler = StandardScaler(
            inputCol="raw_features",
            outputCol="features"
        )
        
        rf = RandomForestClassifier(
            featuresCol="features",
            labelCol="failure_within_24h",
            numTrees=100,
            maxDepth=10
        )
        
        pipeline = Pipeline(stages=[assembler, scaler, rf])
        
        # Train model
        model = pipeline.fit(training_data)
        
        # Save model
        model.write().overwrite().save("hdfs://namenode:9000/models/predictive_maintenance")
        
        return model
```

## Best Practices Summary

### 1. **Architecture Principles**
- **Separation of Concerns**: Distinct layers for ingestion, processing, storage, and analytics
- **Scalability**: Horizontal scaling at each layer
- **Fault Tolerance**: Redundancy and automatic failover
- **Data Governance**: Comprehensive lineage, quality, and security

### 2. **Technology Selection**
- **Proven Technologies**: Use mature, well-supported open-source tools
- **Ecosystem Integration**: Choose tools that work well together
- **Operational Simplicity**: Minimize operational complexity where possible
- **Community Support**: Active communities for troubleshooting and updates

### 3. **Data Management**
- **Schema Evolution**: Plan for schema changes from day one
- **Data Quality**: Implement validation at every stage
- **Partitioning Strategy**: Optimize for query patterns and maintenance
- **Retention Policies**: Implement automated data lifecycle management

### 4. **Operations**
- **Monitoring**: Comprehensive metrics and alerting
- **Automation**: Minimize manual operations
- **Documentation**: Maintain up-to-date architecture and runbooks
- **Disaster Recovery**: Regular backups and tested recovery procedures

### 5. **Security & Compliance**
- **Defense in Depth**: Multiple layers of security
- **Principle of Least Privilege**: Minimal necessary access
- **Audit Everything**: Comprehensive audit trails
- **Encryption**: At rest and in transit

This comprehensive guide provides the foundation for building robust, scalable, and maintainable on-premises data pipelines using open-source technologies, based on proven industry practices from leading technology companies.
