# Apache Iceberg Source Code Guide

## Overview

Apache Iceberg is a high-performance table format for huge analytic datasets. This guide explains the main components of the Iceberg source code and how to navigate and understand the codebase.

## Project Structure

The Iceberg repository is organized as a multi-module Gradle project. Here's the high-level structure:

```
sources/iceberg/
├── api/              # Public API interfaces
├── core/             # Core implementation (reference implementation)
├── common/           # Common utilities
├── data/             # Data reading/writing utilities
├── parquet/          # Parquet file format support
├── orc/              # ORC file format support
├── arrow/            # Arrow integration
├── spark/            # Apache Spark integration
├── flink/            # Apache Flink integration
├── kafka-connect/    # Kafka Connect integration
├── hive-metastore/   # Hive Metastore catalog implementation
├── aws/              # AWS integrations (S3, Glue, DynamoDB)
├── azure/            # Azure integrations
├── gcp/              # Google Cloud Platform integrations
├── format/           # Format specifications (markdown docs)
└── docs/             # Documentation
```

## Core Modules

### 1. **iceberg-api** - The Public API

**Location**: `sources/iceberg/api/`

This module defines the public interfaces that all Iceberg implementations must follow. It's the contract between Iceberg and processing engines.

**Key Packages**:
- `org.apache.iceberg` - Core interfaces (Table, Schema, Snapshot, etc.)
- `org.apache.iceberg.catalog` - Catalog interfaces for table discovery
- `org.apache.iceberg.expressions` - Expression API for filtering
- `org.apache.iceberg.types` - Type system
- `org.apache.iceberg.io` - I/O interfaces
- `org.apache.iceberg.transforms` - Partition transforms

**Important Interfaces**:
- `Table` - Main table interface
- `TableScan` - Interface for reading table data
- `AppendFiles`, `OverwriteFiles`, `DeleteFiles` - Write operations
- `Schema` - Table schema definition
- `Snapshot` - Point-in-time table state
- `PartitionSpec` - Partitioning configuration
- `SortOrder` - Sort order specification

**When to use**: Reference this module when you want to understand what operations are available or when building integrations.

### 2. **iceberg-core** - The Reference Implementation

**Location**: `sources/iceberg/core/`

This is the heart of Iceberg - the reference implementation of the API. Processing engines should depend on this module.

**Key Components**:

#### Table Operations
- `BaseTable` - Main table implementation
- `TableOperations` - Low-level table metadata operations
- `TableMetadata` - Table metadata representation
- `TableMetadataParser` - JSON serialization/deserialization

#### Snapshot Management
- `BaseSnapshot` - Snapshot implementation
- `SnapshotProducer` - Base class for creating snapshots
- `FastAppend` - Optimized append operation
- `MergeAppend` - Append with manifest merging
- `OverwriteFiles` - Overwrite operation

#### Manifest Management
- `ManifestFile` - Manifest file metadata
- `ManifestReader` - Reads manifest files
- `ManifestWriter` - Writes manifest files
- `ManifestGroup` - Groups manifests for scan planning
- `ManifestLists` - Manifest list operations

#### Scanning
- `BaseTableScan` - Table scan implementation
- `DataTableScan` - Scan for data files
- `FileScanTask` - Represents a file to scan
- `ManifestGroup` - Efficient manifest filtering

#### Catalog Implementations
- `BaseMetastoreCatalog` - Base for metastore catalogs
- `hadoop/HadoopCatalog` - Hadoop-based catalog
- `rest/RESTCatalog` - REST catalog client
- `jdbc/JdbcCatalog` - JDBC-based catalog

**When to use**: Study this module to understand how Iceberg works internally or when implementing custom catalogs.

### 3. **iceberg-common** - Shared Utilities

**Location**: `sources/iceberg/common/`

Contains utility classes used across multiple modules.

**Key Components**:
- Collection utilities
- Serialization helpers
- Common data structures

### 4. **iceberg-data** - Data Access Layer

**Location**: `sources/iceberg/data/`

Provides utilities for reading and writing Iceberg tables directly from JVM applications without a processing engine.

**Key Components**:
- `GenericReader` - Generic data reader
- `GenericWriter` - Generic data writer
- Delete file handling
- Data file iteration

**When to use**: When building standalone applications that need to read/write Iceberg tables.

## File Format Modules

### 5. **iceberg-parquet** - Parquet Support

**Location**: `sources/iceberg/parquet/`

Implements reading and writing Parquet files with Iceberg schema and type mappings.

**Key Components**:
- `ParquetReader` - Parquet file reader
- `ParquetWriter` - Parquet file writer
- Type conversions between Iceberg and Parquet
- Predicate pushdown

### 6. **iceberg-orc** - ORC Support

**Location**: `sources/iceberg/orc/`

Implements reading and writing ORC files with Iceberg schema and type mappings.

### 7. **iceberg-arrow** - Arrow Integration

**Location**: `sources/iceberg/arrow/`

Provides integration with Apache Arrow for in-memory columnar data processing.

## Processing Engine Integrations

### 8. **iceberg-spark** - Apache Spark Integration

**Location**: `sources/iceberg/spark/`

Implements Spark's DataSource V2 API for Iceberg tables. Contains version-specific implementations for Spark 3.4, 3.5, and 4.0.

**Key Components**:
- Spark SQL extensions
- Custom procedures
- Read/write implementations
- Streaming support

### 9. **iceberg-flink** - Apache Flink Integration

**Location**: `sources/iceberg/flink/`

Provides Flink connectors for reading and writing Iceberg tables.

### 10. **iceberg-kafka-connect** - Kafka Connect

**Location**: `sources/iceberg/kafka-connect/`

Kafka Connect sink connector for writing Kafka topics to Iceberg tables.

## Cloud Storage Integrations

### 11. **iceberg-aws** - AWS Integration

**Location**: `sources/iceberg/aws/`

**Key Components**:
- S3 file I/O implementation
- AWS Glue catalog
- DynamoDB lock manager
- Lake Formation integration

### 12. **iceberg-azure** - Azure Integration

**Location**: `sources/iceberg/azure/`

Azure Data Lake Storage (ADLS) integration.

### 13. **iceberg-gcp** - Google Cloud Integration

**Location**: `sources/iceberg/gcp/`

Google Cloud Storage (GCS) integration.

## Catalog Implementations

### 14. **iceberg-hive-metastore** - Hive Metastore Catalog

**Location**: `sources/iceberg/hive-metastore/`

Implements Iceberg catalog using Hive Metastore as the backend.

### 15. **iceberg-nessie** - Nessie Catalog

**Location**: `sources/iceberg/nessie/`

Integration with Project Nessie for Git-like version control of tables.

## Understanding the Iceberg Architecture

### The Metadata Layer

Iceberg uses a three-level metadata structure:

1. **Metadata File** (JSON)
   - Contains table schema, partition spec, sort order
   - Points to current snapshot
   - Stored as `v{N}.metadata.json`

2. **Manifest List** (Avro)
   - Lists all manifest files for a snapshot
   - Contains partition-level statistics
   - Enables efficient scan planning

3. **Manifest Files** (Avro)
   - Lists data files and their metadata
   - Contains file-level statistics (row counts, column bounds)
   - Reused across snapshots when unchanged

4. **Data Files** (Parquet/ORC/Avro)
   - Actual table data
   - Immutable once written

### Key Concepts

#### Snapshots
- Represent table state at a point in time
- Immutable and identified by snapshot ID
- Enable time travel and rollback

#### Optimistic Concurrency
- Multiple writers can work concurrently
- Atomic metadata file swap for commits
- Retry on conflict with updated base

#### Partition Evolution
- Partition spec can change over time
- Old data doesn't need rewriting
- Scan planning handles multiple partition specs

#### Schema Evolution
- Add, drop, rename, reorder columns
- Type promotion (int → long)
- Maintains column IDs for compatibility

## How to Read the Code

### Starting Points

1. **Understanding the API**: Start with `iceberg-api/src/main/java/org/apache/iceberg/Table.java`
2. **Table Operations**: Look at `iceberg-core/src/main/java/org/apache/iceberg/BaseTable.java`
3. **Writing Data**: Study `FastAppend.java` and `MergeAppend.java`
4. **Reading Data**: Examine `BaseTableScan.java` and `ManifestGroup.java`
5. **Metadata Format**: Read `TableMetadata.java` and `TableMetadataParser.java`

### Common Workflows

#### Creating a Table
```
Catalog → createTable() → TableOperations → TableMetadata → commit()
```

#### Appending Data
```
Table → newAppend() → AppendFiles → add(DataFile) → commit()
→ SnapshotProducer → ManifestWriter → TableOperations.commit()
```

#### Scanning a Table
```
Table → newScan() → TableScan → planFiles()
→ ManifestGroup → filter manifests → read manifests → FileScanTask
```

## Format Specifications

**Location**: `sources/iceberg/format/`

- `spec.md` - Complete Iceberg table format specification
- `puffin-spec.md` - Puffin file format for statistics
- `view-spec.md` - Iceberg views specification

**When to use**: Reference these when implementing new features or understanding the on-disk format.

## Testing

Tests are located in `src/test/` directories within each module. Key test patterns:

- Unit tests for individual components
- Integration tests for end-to-end workflows
- Compatibility tests across versions

## Building the Project

```bash
# Build everything
./gradlew build

# Build without tests
./gradlew build -x test -x integrationTest

# Build specific module
./gradlew :iceberg-core:build

# Fix code style
./gradlew spotlessApply
```

## Key Design Principles

1. **Immutability**: Data files and snapshots are immutable
2. **Atomic Operations**: Metadata updates are atomic
3. **Optimistic Concurrency**: No locks during writes
4. **O(1) Planning**: Scan planning uses constant remote calls
5. **Schema Evolution**: Safe schema changes without rewrites
6. **Hidden Partitioning**: Users query by data values, not partitions

## Common Patterns

### Parser Classes
Many classes have corresponding `*Parser` classes (e.g., `TableMetadataParser`, `SchemaParser`) that handle JSON serialization.

### Base Classes
Abstract `Base*` classes provide common functionality (e.g., `BaseTable`, `BaseScan`, `BaseSnapshot`).

### Builder Pattern
Many objects use builders (e.g., `Schema.Builder`, `PartitionSpec.Builder`).

### Visitor Pattern
Used extensively for expressions, types, and schema traversal.

## Resources

- **Official Documentation**: https://iceberg.apache.org/docs/latest/
- **Format Spec**: `sources/iceberg/format/spec.md`
- **Contributing Guide**: https://iceberg.apache.org/contribute/
- **Community**: dev@iceberg.apache.org

## Next Steps

1. Read the format specification in `format/spec.md`
2. Explore the API interfaces in `iceberg-api`
3. Study the core implementation in `iceberg-core`
4. Look at integration examples in `iceberg-spark` or `iceberg-flink`
5. Run the examples in `examples/` directory

---

**Note**: This guide is based on the Java implementation. Other language implementations (Python, Go, Rust, C++) follow similar architectural patterns but with language-specific idioms.
