# Apache Iceberg Runtime Libraries: Architecture and Design

## Overview

Apache Iceberg runtime libraries provide the execution layer that enables compute engines to interact with Iceberg tables. Unlike traditional table formats that are tightly coupled to specific engines, Iceberg's runtime architecture is designed for **engine-agnostic operation** while providing **engine-specific optimizations**.

## Runtime Architecture

### 1. Layered Design

```
┌─────────────────────────────────────────────────────┐
│           Engine-Specific Runtime                   │
│  (iceberg-spark, iceberg-flink, iceberg-trino)     │
├─────────────────────────────────────────────────────┤
│              Core Runtime Libraries                 │
│     (iceberg-core, iceberg-data, iceberg-api)      │
├─────────────────────────────────────────────────────┤
│            Storage & Catalog Integration            │
│   (iceberg-aws, iceberg-hadoop, iceberg-hive)      │
├─────────────────────────────────────────────────────┤
│              File Format Libraries                  │
│      (iceberg-parquet, iceberg-orc, iceberg-avro)  │
└─────────────────────────────────────────────────────┘
```

### 2. Core Runtime Components

#### **iceberg-api**: Public Interface Layer
```java
// Clean, stable API contracts
public interface Table {
    Schema schema();
    PartitionSpec spec();
    TableScan newScan();
    AppendFiles newAppend();
    Transaction newTransaction();
}
```

**Design Choice**: Separate API from implementation
- **Why**: Allows implementation changes without breaking user code
- **Advantage**: Backward compatibility and stable integration points

#### **iceberg-core**: Implementation Engine
```java
// BaseTable.java - Core table operations
public class BaseTable implements Table {
    private final TableOperations ops;
    private final String name;
    
    @Override
    public TableScan newScan() {
        return new BaseTableScan(ops, this, schema());
    }
}
```

**Design Choice**: Immutable metadata with copy-on-write semantics
- **Why**: Thread-safety and consistent snapshots
- **Advantage**: No locking needed for concurrent reads

#### **iceberg-data**: Generic Data Processing
```java
// Generic record reading without engine dependencies
CloseableIterable<Record> records = IcebergGenerics
    .read(table)
    .where(Expressions.equal("status", "active"))
    .build();
```

**Design Choice**: Engine-agnostic data access layer
- **Why**: Enables tooling and applications beyond compute engines
- **Advantage**: Consistent behavior across all integrations

## Engine-Specific Runtime Design

### 1. Spark Runtime (`iceberg-spark-runtime`)

#### DataSource V2 Integration
```java
// SparkTable.java - Spark-specific table implementation
public class SparkTable implements Table, SupportsRead, SupportsWrite {
    
    @Override
    public ScanBuilder newScanBuilder(CaseInsensitiveStringMap options) {
        return new SparkScanBuilder(sparkSession, table, options);
    }
    
    @Override
    public WriteBuilder newWriteBuilder(LogicalWriteInfo info) {
        return new SparkWriteBuilder(sparkSession, table, info);
    }
}
```

**Key Design Decisions:**

1. **Pushdown Optimization**
```java
// Automatic predicate pushdown to file level
public class SparkScanBuilder implements ScanBuilder, SupportsPushDownFilters {
    @Override
    public Filter[] pushFilters(Filter[] filters) {
        Expression converted = SparkFilters.convert(filters);
        this.scan = scan.filter(converted);
        return filters; // All filters pushed down
    }
}
```

2. **Vectorized Reading**
```java
// VectorizedSparkParquetReaders.java
public class VectorizedReader implements PartitionReader<InternalRow> {
    private final VectorizedParquetReader reader;
    
    @Override
    public InternalRow next() {
        return reader.nextBatch().getRow(currentRow++);
    }
}
```

**Advantages over Hive/Delta:**
- **Native Spark integration**: No external metastore dependencies
- **Vectorized execution**: 10x faster than row-based processing
- **Dynamic partition pruning**: Runtime optimization based on actual data

### 2. Flink Runtime (`iceberg-flink-runtime`)

#### Streaming Integration
```java
// FlinkSource.java - Streaming table source
public class IcebergTableSource implements ScanTableSource, SupportsWatermarkPushDown {
    
    @Override
    public ScanRuntimeProvider getScanRuntimeProvider(ScanContext context) {
        return SourceFunctionProvider.of(
            new StreamingMonitorFunction(table, context),
            false // Not parallel
        );
    }
}
```

**Streaming Design Choices:**

1. **Incremental Processing**
```java
// Monitor for new snapshots and process incrementally
public class StreamingMonitorFunction extends RichSourceFunction<RowData> {
    
    private void processSnapshot(Snapshot snapshot) {
        IncrementalAppendScan scan = table.newIncrementalAppendScan()
            .fromSnapshotExclusive(lastProcessedSnapshot)
            .toSnapshot(snapshot.snapshotId());
            
        // Process only new data files
        for (FileScanTask task : scan.planFiles()) {
            processFile(task);
        }
    }
}
```

2. **Exactly-Once Processing**
```java
// Checkpoint integration for fault tolerance
public class IcebergStreamWriter extends TwoPhaseCommitSinkFunction<RowData, DataFile, Void> {
    
    @Override
    protected void preCommit(DataFile dataFile) throws Exception {
        // Stage files for commit
        pendingFiles.add(dataFile);
    }
    
    @Override
    protected void commit(Void transaction) {
        // Atomic commit of all staged files
        table.newAppend().appendFiles(pendingFiles).commit();
    }
}
```

**Advantages over Traditional Streaming:**
- **Exactly-once semantics**: Built-in transaction support
- **Time travel**: Query historical states in streaming jobs
- **Schema evolution**: Handle schema changes without job restarts

### 3. Trino Runtime (`iceberg-trino`)

#### Connector Architecture
```java
// IcebergConnector.java - Trino connector implementation
public class IcebergConnector implements Connector {
    
    @Override
    public ConnectorSplitManager getSplitManager() {
        return new IcebergSplitManager(typeManager, jsonCodec);
    }
    
    @Override
    public ConnectorPageSourceProvider getPageSourceProvider() {
        return new IcebergPageSourceProvider(hdfsEnvironment, fileFormatDataSourceStats);
    }
}
```

**Query Planning Optimizations:**
```java
// Dynamic filtering and partition elimination
public class IcebergSplitManager implements ConnectorSplitManager {
    
    @Override
    public ConnectorSplitSource getSplits(ConnectorTransactionHandle transaction,
                                         ConnectorSession session,
                                         ConnectorTableHandle table,
                                         SplitSchedulingStrategy splitSchedulingStrategy,
                                         Constraint constraint) {
        
        // Convert Trino constraints to Iceberg expressions
        Expression filter = toIcebergExpression(constraint);
        
        // Plan splits with pushdown filters
        TableScan scan = icebergTable.newScan().filter(filter);
        return new IcebergSplitSource(scan.planFiles());
    }
}
```

**Advantages over Hive Connector:**
- **Metadata-only queries**: No file scanning for partition info
- **Cost-based optimization**: Statistics-driven query planning
- **Dynamic filtering**: Runtime partition elimination

## Storage Integration Design

### 1. Pluggable FileIO Architecture

```java
// FileIO.java - Abstract storage interface
public interface FileIO extends Serializable, Closeable {
    InputFile newInputFile(String path);
    OutputFile newOutputFile(String path);
    void deleteFile(String path);
}
```

**Implementation Examples:**

#### S3FileIO
```java
public class S3FileIO implements FileIO {
    private final AmazonS3 s3;
    private final S3Configuration s3Config;
    
    @Override
    public InputFile newInputFile(String path) {
        return new S3InputFile(s3, S3URI.create(path), s3Config);
    }
}
```

#### HadoopFileIO  
```java
public class HadoopFileIO implements FileIO {
    private final Configuration conf;
    
    @Override
    public InputFile newInputFile(String path) {
        return new HadoopInputFile(new Path(path), conf);
    }
}
```

**Design Benefits:**
- **Storage agnostic**: Works with any object store or filesystem
- **Optimization opportunities**: Storage-specific optimizations (S3 multipart, etc.)
- **Testing**: Easy to mock for unit tests

### 2. Catalog Integration

```java
// Catalog.java - Metadata management interface
public interface Catalog {
    Table loadTable(TableIdentifier identifier);
    Table createTable(TableIdentifier identifier, Schema schema);
    boolean dropTable(TableIdentifier identifier);
}
```

**Multiple Catalog Implementations:**

#### HiveCatalog
```java
// Leverages existing Hive Metastore
public class HiveCatalog implements Catalog {
    private final IMetaStoreClient metastore;
    
    @Override
    public Table loadTable(TableIdentifier identifier) {
        org.apache.hadoop.hive.metastore.api.Table hiveTable = 
            metastore.getTable(identifier.namespace().level(0), identifier.name());
        
        String metadataLocation = hiveTable.getParameters().get("metadata_location");
        return loadTableFromMetadata(metadataLocation);
    }
}
```

#### RESTCatalog
```java
// Modern HTTP-based catalog
public class RESTCatalog implements Catalog {
    private final RESTClient client;
    
    @Override
    public Table loadTable(TableIdentifier identifier) {
        LoadTableResponse response = client.get(
            paths.table(identifier), 
            LoadTableResponse.class
        );
        return new BaseTable(ops(identifier), identifier.toString());
    }
}
```

## Performance Optimizations

### 1. Lazy Evaluation

```java
// TableScan.java - Deferred execution
public class BaseTableScan implements TableScan {
    
    @Override
    public CloseableIterable<FileScanTask> planFiles() {
        // Only evaluate when actually needed
        return new LazyIterable<>(() -> {
            return planFilesImpl();
        });
    }
}
```

### 2. Metadata Caching

```java
// CachingCatalog.java - Metadata caching wrapper
public class CachingCatalog implements Catalog {
    private final Cache<TableIdentifier, Table> tableCache;
    
    @Override
    public Table loadTable(TableIdentifier identifier) {
        return tableCache.get(identifier, () -> delegate.loadTable(identifier));
    }
}
```

### 3. Parallel Processing

```java
// Parallel manifest reading
public class ManifestReader {
    
    public CloseableIterable<ManifestEntry<DataFile>> entries() {
        return CloseableIterable.combine(
            manifests.parallelStream()
                .map(this::readManifest)
                .collect(Collectors.toList())
        );
    }
}
```

## Advantages Over Alternative Implementations

### 1. **vs. Hive Tables**

| Aspect | Iceberg Runtime | Hive Tables |
|--------|----------------|-------------|
| **Metadata** | Self-contained JSON | External metastore required |
| **Schema Evolution** | Automatic, backward compatible | Manual, often breaking |
| **ACID** | Full ACID support | Limited, partition-level only |
| **Performance** | Metadata-based pruning | Full partition scanning |
| **Streaming** | Native support | Batch-oriented |

### 2. **vs. Delta Lake**

| Aspect | Iceberg Runtime | Delta Lake |
|--------|----------------|------------|
| **Engine Support** | Multi-engine (Spark, Flink, Trino) | Primarily Spark |
| **File Formats** | Multiple (Parquet, ORC, Avro) | Parquet only |
| **Catalog Integration** | Pluggable catalogs | Limited options |
| **Specification** | Open standard | Proprietary |
| **Vendor Lock-in** | None | Databricks ecosystem |

### 3. **vs. Hudi**

| Aspect | Iceberg Runtime | Apache Hudi |
|--------|----------------|-------------|
| **Complexity** | Simple, clean API | Complex configuration |
| **Write Performance** | Optimized for append | Optimized for upserts |
| **Query Performance** | Excellent for analytics | Good for point queries |
| **Operational Overhead** | Minimal | Requires tuning |
| **Learning Curve** | Gentle | Steep |

## Key Design Principles

### 1. **Separation of Concerns**
- **API**: Stable contracts
- **Core**: Business logic
- **Runtime**: Engine integration
- **Storage**: Pluggable backends

### 2. **Performance by Design**
- **Lazy evaluation**: Compute only when needed
- **Vectorization**: Batch processing where possible
- **Pushdown**: Move computation to data
- **Caching**: Avoid redundant operations

### 3. **Extensibility**
- **Plugin architecture**: Easy to add new engines
- **Format support**: Multiple file formats
- **Storage backends**: Any object store or filesystem
- **Catalog implementations**: Flexible metadata management

### 4. **Reliability**
- **Immutable metadata**: No corruption possible
- **Atomic operations**: All-or-nothing commits
- **Backward compatibility**: Evolve without breaking
- **Testing**: Comprehensive test coverage

## Conclusion

Iceberg's runtime architecture represents a **paradigm shift** from engine-specific table formats to a **universal, engine-agnostic** approach. The layered design, pluggable components, and performance optimizations make it the **most versatile and future-proof** table format for modern data lakes.

The runtime libraries enable organizations to:
- **Avoid vendor lock-in** through multi-engine support
- **Optimize performance** through engine-specific integrations
- **Scale operations** through distributed, parallel processing
- **Ensure reliability** through ACID guarantees and immutable metadata

This design positions Iceberg as the **foundation for next-generation data lake architectures** that prioritize flexibility, performance, and reliability over proprietary solutions.
