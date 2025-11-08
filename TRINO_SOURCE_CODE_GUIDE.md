# Trino Source Code Guide

## Overview

Trino is a fast distributed SQL query engine for big data analytics. It allows you to query data where it lives, including Hive, Cassandra, relational databases, and proprietary data stores. This guide explains the main components of the Trino source code and how to navigate and understand the codebase.

## Project Structure

Trino is organized as a multi-module Maven project. Here's the high-level structure:

```
sources/trino/
├── client/           # Client libraries (CLI, JDBC, Java client)
├── core/             # Core engine components
├── lib/              # Shared libraries and utilities
├── plugin/           # Connector plugins and extensions
├── service/          # Additional services (proxy, verifier)
├── testing/          # Testing infrastructure and utilities
└── docs/             # Documentation
```

## Core Modules

### 1. **trino-spi** - Service Provider Interface

**Location**: `sources/trino/core/trino-spi/`

The SPI (Service Provider Interface) defines the plugin API that all connectors and extensions must implement. This is the contract between Trino core and plugins.

**Key Packages**:
- `io.trino.spi.connector` - Connector interfaces (the main plugin type)
- `io.trino.spi.type` - Type system
- `io.trino.spi.block` - Columnar data representation
- `io.trino.spi.predicate` - Predicate pushdown
- `io.trino.spi.security` - Security and access control
- `io.trino.spi.function` - User-defined functions
- `io.trino.spi.eventlistener` - Event listener interface
- `io.trino.spi.exchange` - Data exchange interfaces

**Important Interfaces**:
- `Plugin` - Main plugin interface
- `Connector` - Represents a data source connection
- `ConnectorMetadata` - Metadata operations (tables, columns, etc.)
- `ConnectorSplitManager` - Splits data for parallel processing
- `ConnectorPageSource` - Reads data pages
- `ConnectorPageSink` - Writes data pages
- `ConnectorRecordSetProvider` - Alternative to page-based reading

**When to use**: Study this module when building connectors or understanding the plugin architecture.

### 2. **trino-main** - Query Engine Core

**Location**: `sources/trino/core/trino-main/`

This is the heart of Trino - the distributed query execution engine.

**Key Components**:

#### Query Planning & Optimization
- `sql/planner` - Query planner (logical and distributed plans)
- `sql/analyzer` - Semantic analysis
- `cost` - Cost-based optimizer (CBO)
- `metadata` - Metadata management
- `sql/tree` - SQL AST (Abstract Syntax Tree)

#### Query Execution
- `operator` - Physical operators (scan, filter, join, aggregate, etc.)
- `execution` - Task execution and scheduling
- `dispatcher` - Query dispatcher and coordinator
- `split` - Split management and assignment
- `exchange` - Data exchange between stages

#### Memory & Resource Management
- `memory` - Memory management and tracking
- `spiller` - Disk spilling for large operations
- `operator/aggregation` - Aggregation operators

#### Server Components
- `server` - HTTP server and REST APIs
- `security` - Authentication and authorization
- `transaction` - Transaction management
- `connector` - Connector lifecycle management

**When to use**: Study this module to understand how queries are planned, optimized, and executed.

### 3. **trino-parser** - SQL Parser

**Location**: `sources/trino/core/trino-parser/`

Parses SQL statements into an Abstract Syntax Tree (AST).

**Key Components**:
- ANTLR-based SQL grammar
- AST node definitions
- Expression parsing

### 4. **trino-grammar** - SQL Grammar Definition

**Location**: `sources/trino/core/trino-grammar/`

Contains the ANTLR grammar files that define Trino's SQL syntax.

### 5. **trino-server** - Server Assembly

**Location**: `sources/trino/core/trino-server/`

Packages the Trino server distribution with all necessary components.

### 6. **trino-web-ui** - Web Interface

**Location**: `sources/trino/core/trino-web-ui/`

React-based web UI for monitoring queries and cluster status.

## Client Modules

### 7. **trino-client** - Java Client Library

**Location**: `sources/trino/client/trino-client/`

Java client library for connecting to Trino programmatically.

### 8. **trino-jdbc** - JDBC Driver

**Location**: `sources/trino/client/trino-jdbc/`

JDBC driver implementation for Trino.

### 9. **trino-cli** - Command Line Interface

**Location**: `sources/trino/client/trino-cli/`

Interactive command-line client for running queries.

## Library Modules

### 10. **trino-parquet** - Parquet Reader/Writer

**Location**: `sources/trino/lib/trino-parquet/`

High-performance Parquet file format support with predicate pushdown and column pruning.

### 11. **trino-orc** - ORC Reader/Writer

**Location**: `sources/trino/lib/trino-orc/`

Optimized ORC file format support.

### 12. **trino-hive-formats** - Hive File Formats

**Location**: `sources/trino/lib/trino-hive-formats/`

Support for various Hive file formats (RCFile, SequenceFile, etc.).

### 13. **trino-filesystem** - Filesystem Abstraction

**Location**: `sources/trino/lib/trino-filesystem/`

Unified filesystem interface for different storage systems.

**Related Modules**:
- `trino-filesystem-s3` - S3 implementation
- `trino-filesystem-azure` - Azure Blob Storage
- `trino-filesystem-gcs` - Google Cloud Storage
- `trino-filesystem-alluxio` - Alluxio integration

### 14. **trino-metastore** - Metastore Client

**Location**: `sources/trino/lib/trino-metastore/`

Hive Metastore client implementation used by multiple connectors.

### 15. **trino-plugin-toolkit** - Plugin Utilities

**Location**: `sources/trino/lib/trino-plugin-toolkit/`

Common utilities and base classes for building plugins.

### 16. **trino-cache** - Caching Infrastructure

**Location**: `sources/trino/lib/trino-cache/`

Caching layer for file systems and metadata.

## Plugin Modules (Connectors)

### Data Lake Connectors

#### 17. **trino-iceberg** - Apache Iceberg Connector

**Location**: `sources/trino/plugin/trino-iceberg/`

Connector for querying Apache Iceberg tables with full support for time travel, schema evolution, and ACID transactions.

#### 18. **trino-hive** - Hive Connector

**Location**: `sources/trino/plugin/trino-hive/`

Connector for Hive tables, supporting various file formats and metastores.

#### 19. **trino-delta-lake** - Delta Lake Connector

**Location**: `sources/trino/plugin/trino-delta-lake/`

Connector for Delta Lake tables.

#### 20. **trino-hudi** - Apache Hudi Connector

**Location**: `sources/trino/plugin/trino-hudi/`

Connector for Apache Hudi tables.

### JDBC-Based Connectors

#### 21. **trino-base-jdbc** - JDBC Base Classes

**Location**: `sources/trino/plugin/trino-base-jdbc/`

Base classes and utilities for building JDBC-based connectors.

#### 22. Database Connectors

All JDBC-based database connectors:
- `trino-postgresql` - PostgreSQL
- `trino-mysql` - MySQL
- `trino-oracle` - Oracle Database
- `trino-sqlserver` - Microsoft SQL Server
- `trino-redshift` - Amazon Redshift
- `trino-snowflake` - Snowflake
- `trino-clickhouse` - ClickHouse
- `trino-mariadb` - MariaDB
- `trino-singlestore` - SingleStore
- `trino-vertica` - Vertica
- `trino-exasol` - Exasol

### NoSQL & Specialized Connectors

- `trino-mongodb` - MongoDB
- `trino-cassandra` - Apache Cassandra
- `trino-elasticsearch` - Elasticsearch
- `trino-opensearch` - OpenSearch
- `trino-redis` - Redis
- `trino-kafka` - Apache Kafka
- `trino-pinot` - Apache Pinot
- `trino-druid` - Apache Druid
- `trino-bigquery` - Google BigQuery
- `trino-prometheus` - Prometheus

### Utility Connectors

- `trino-tpch` - TPC-H benchmark data generator
- `trino-tpcds` - TPC-DS benchmark data generator
- `trino-memory` - In-memory tables
- `trino-blackhole` - Blackhole connector (for testing)
- `trino-jmx` - JMX metrics connector
- `trino-faker` - Fake data generator

### Extension Plugins

- `trino-ml` - Machine learning functions
- `trino-geospatial` - Geospatial functions
- `trino-ai-functions` - AI/ML integration functions
- `trino-functions-python` - Python UDF support
- `trino-teradata-functions` - Teradata compatibility functions

### Infrastructure Plugins

- `trino-password-authenticators` - Password authentication
- `trino-ldap-group-provider` - LDAP group provider
- `trino-resource-group-managers` - Resource group management
- `trino-session-property-managers` - Session property management
- `trino-http-event-listener` - HTTP event listener
- `trino-kafka-event-listener` - Kafka event listener
- `trino-openlineage` - OpenLineage integration
- `trino-ranger` - Apache Ranger integration
- `trino-opa` - Open Policy Agent integration

## Understanding Trino Architecture

### Query Execution Flow

1. **Client Submission**
   - Client submits SQL query via HTTP/JDBC
   - Query enters through `DispatchManager`

2. **Parsing & Analysis**
   - `SqlParser` parses SQL into AST
   - `Analyzer` performs semantic analysis
   - Resolves tables, columns, functions

3. **Planning**
   - `LogicalPlanner` creates logical plan
   - `PlanOptimizers` apply optimization rules
   - Cost-based optimizer chooses best plan
   - `DistributedPlanner` creates distributed execution plan

4. **Scheduling**
   - Query broken into stages and tasks
   - `SqlQueryScheduler` schedules tasks on workers
   - `SplitManager` generates data splits

5. **Execution**
   - Workers execute tasks using operators
   - Data flows through operator pipeline
   - Results exchanged between stages

6. **Result Delivery**
   - Final results buffered and returned to client
   - Streaming or buffered depending on query type

### Key Concepts

#### Connectors
- Plugins that connect Trino to data sources
- Implement SPI interfaces
- Provide metadata, splits, and data access

#### Splits
- Unit of parallelism for data reading
- Represent a portion of a table to scan
- Assigned to workers for processing

#### Pages
- Columnar data structure (like Arrow RecordBatch)
- Efficient in-memory representation
- Passed between operators

#### Operators
- Physical execution units (Scan, Filter, Join, etc.)
- Process pages of data
- Pipelined execution model

#### Stages
- Collection of tasks executing same plan fragment
- Can be distributed across multiple workers
- Connected via data exchanges

#### Tasks
- Instance of a stage running on a worker
- Executes operator pipeline
- Processes splits and produces pages

### Memory Management

- **User Memory**: Query data processing
- **System Memory**: Internal structures
- **Reserved Memory**: Reserved for specific queries
- Memory pools prevent OOM and enable spilling

### Distributed Execution

- **Coordinator**: Plans queries, schedules tasks
- **Workers**: Execute tasks, process data
- **Discovery Service**: Node registration and discovery
- **Exchange**: Data shuffle between stages

## How to Read the Code

### Starting Points

1. **Understanding SPI**: Start with `trino-spi/src/main/java/io/trino/spi/Plugin.java`
2. **Query Flow**: Follow `DispatchManager` → `SqlQueryExecution` → `SqlQueryScheduler`
3. **Planning**: Study `LogicalPlanner` and `PlanOptimizers`
4. **Execution**: Look at `SqlTaskExecution` and operator implementations
5. **Connector Example**: Examine `trino-memory` or `trino-tpch` for simple examples

### Common Workflows

#### Building a Connector
```
Implement Plugin → ConnectorFactory → Connector
→ ConnectorMetadata + ConnectorSplitManager + ConnectorPageSourceProvider
```

#### Query Execution
```
SQL → Parser → Analyzer → LogicalPlanner → Optimizer
→ DistributedPlanner → Scheduler → Task Execution → Results
```

#### Reading Data
```
ConnectorSplitManager.getSplits() → ConnectorPageSourceProvider.createPageSource()
→ ConnectorPageSource.getNextPage() → Operators process pages
```

## Building Trino

### Prerequisites
- Java 24.0.1+ (64-bit)
- Maven 3.6+
- Docker (for tests)

### Build Commands

```bash
# Full build with tests
./mvnw clean install

# Build without tests (faster)
./mvnw clean install -DskipTests

# Build specific module
./mvnw clean install -pl :trino-iceberg -am

# Run checkstyle
./mvnw validate

# Format license headers
./mvnw license:format
```

### Running Trino

#### Development Server
```bash
# Run TpchQueryRunner for quick testing
# Main class: io.trino.tpch.TpchQueryRunner

# Or run full server
# Main class: io.trino.server.DevelopmentServer
# Working directory: testing/trino-server-dev
```

#### CLI
```bash
client/trino-cli/target/trino-cli-*-executable.jar
```

## Code Style Guidelines

### Key Principles

1. **Readability over rules** - Code should be easy to understand
2. **Consistency** - Follow patterns in surrounding code
3. **Avoid abbreviations** - Use clear, descriptive names
4. **Use streams** - Prefer stream API when appropriate
5. **Avoid mocks** - Write testable code, hand-write test doubles
6. **Use AssertJ** - For complex assertions
7. **Avoid `var`** - Explicit types preferred
8. **Prefer Guava immutable collections** - Deterministic iteration
9. **Avoid default in enum switches** - Let compiler catch missing cases

### Error Handling

Categorize errors with error codes:
```java
throw new TrinoException(HIVE_TOO_MANY_OPEN_PARTITIONS, "Too many partitions");
```

### String Formatting

Use `format()` (statically imported):
```java
format("Session property %s is invalid: %s", name, value)
```

## Testing

### Test Structure
- Unit tests in `src/test/java`
- Integration tests in separate modules
- Product tests in `testing/trino-product-tests`

### Test Utilities
- `testing/trino-testing` - Core testing utilities
- `testing/trino-testing-containers` - Docker test containers
- Query runners for each connector

## Key Design Patterns

### Visitor Pattern
Used extensively for:
- SQL AST traversal
- Plan node traversal
- Type system operations

### Builder Pattern
Many objects use builders:
- `Session.builder()`
- `TableMetadata.builder()`

### Factory Pattern
- `ConnectorFactory` for creating connectors
- `PageSourceProvider` for creating page sources

### Operator Pipeline
- Operators form a pipeline
- Pull-based execution model
- Pages flow through operators

## Plugin Development

### Creating a Connector

1. **Implement Plugin interface**
```java
public class MyPlugin implements Plugin {
    @Override
    public Iterable<ConnectorFactory> getConnectorFactories() {
        return ImmutableList.of(new MyConnectorFactory());
    }
}
```

2. **Implement ConnectorFactory**
```java
public class MyConnectorFactory implements ConnectorFactory {
    @Override
    public Connector create(String catalogName, Map<String, String> config, ConnectorContext context) {
        return new MyConnector(...);
    }
}
```

3. **Implement Connector and required services**
- `ConnectorMetadata` - Table/column metadata
- `ConnectorSplitManager` - Data splitting
- `ConnectorPageSourceProvider` - Data reading
- `ConnectorPageSinkProvider` - Data writing (optional)

4. **Package as plugin**
- Create `META-INF/services/io.trino.spi.Plugin` file
- List your plugin class

## Resources

- **Official Documentation**: https://trino.io/docs/current/
- **Developer Guide**: https://trino.io/docs/current/develop.html
- **SPI Overview**: https://trino.io/docs/current/develop/spi-overview.html
- **Community**: https://trino.io/slack.html
- **Book**: Trino: The Definitive Guide

## Important Directories

- `/core/trino-spi/` - Plugin API definitions
- `/core/trino-main/` - Query engine implementation
- `/plugin/` - All connector implementations
- `/lib/` - Shared libraries
- `/testing/` - Testing infrastructure
- `/docs/` - Documentation source

## Next Steps

1. Read the [Developer Guide](https://trino.io/docs/current/develop.html)
2. Explore the SPI in `trino-spi`
3. Study a simple connector like `trino-memory` or `trino-tpch`
4. Understand query planning in `trino-main/sql/planner`
5. Look at operator implementations in `trino-main/operator`
6. Run the development server and experiment

---

**Note**: Trino is a fast-moving project with frequent releases. This guide is based on version 479-SNAPSHOT. Check the official documentation for the latest information.
