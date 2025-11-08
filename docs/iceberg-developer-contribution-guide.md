# Apache Iceberg Developer Contribution Guide

## Table of Contents
1. [Data Processing Fundamentals](#data-processing-fundamentals)
2. [Storage Engine Concepts](#storage-engine-concepts)
3. [Iceberg Architecture Deep Dive](#iceberg-architecture-deep-dive)
4. [Core Components](#core-components)
5. [Development Environment Setup](#development-environment-setup)
6. [Contributing Guidelines](#contributing-guidelines)
7. [Code Structure](#code-structure)
8. [Testing Framework](#testing-framework)

## Data Processing Fundamentals

### 1. Columnar vs Row Storage

#### Row-Based Storage (Traditional)
```
Record 1: [ID=1, Name="Alice", Age=25, Salary=50000]
Record 2: [ID=2, Name="Bob", Age=30, Salary=60000]
Record 3: [ID=3, Name="Carol", Age=28, Salary=55000]

Storage Layout:
[1|Alice|25|50000][2|Bob|30|60000][3|Carol|28|55000]

Pros: Fast for OLTP (insert/update single records)
Cons: Inefficient for analytics (must read entire rows)
```

#### Columnar Storage (Iceberg's Approach)
```
Column Layout:
IDs:      [1][2][3]
Names:    [Alice][Bob][Carol]  
Ages:     [25][30][28]
Salaries: [50000][60000][55000]

Pros: 
- Better compression (similar values together)
- Faster analytics (read only needed columns)
- Vectorized processing friendly
- Better cache utilization

Cons: Slower for single-row operations
```

### 2. File Formats in Iceberg

#### Parquet (Primary Format)
```java
// ParquetWriter example in Iceberg
public class IcebergParquetWriter {
    
    public static void writeParquetFile(Schema schema, List<Record> records, OutputFile output) {
        try (FileAppender<Record> appender = Parquet.write(output)
                .schema(schema)
                .createWriterFunc(GenericParquetWriter::buildWriter)
                .build()) {
            
            for (Record record : records) {
                appender.add(record);
            }
        }
    }
}
```

**Key Parquet Concepts:**
- **Row Groups**: Horizontal partitions (default: 128MB)
- **Column Chunks**: Data for one column in a row group
- **Pages**: Smallest unit of compression/encoding
- **Statistics**: Min/max values per column chunk

#### ORC Support
```java
// ORC writer integration
public class IcebergOrcWriter {
    
    public static FileAppender<Record> createOrcWriter(OutputFile output, Schema schema) {
        return ORC.write(output)
                .schema(schema)
                .createWriterFunc(GenericOrcWriter::buildWriter)
                .build();
    }
}
```

### 3. Compression and Encoding

#### Compression Algorithms
```java
// Compression configuration in Iceberg
Map<String, String> properties = Map.of(
    "write.parquet.compression-codec", "zstd",     // Fast compression
    "write.parquet.compression-level", "3",        // Balance speed/size
    "write.orc.compression-codec", "lz4"           // ORC compression
);
```

**Compression Trade-offs:**
- **GZIP**: High compression, slower
- **Snappy**: Fast, moderate compression  
- **LZ4**: Very fast, lower compression
- **ZSTD**: Best balance of speed and compression

#### Encoding Techniques
```java
// Dictionary encoding example
public class DictionaryEncoder {
    
    private final Map<String, Integer> dictionary = new HashMap<>();
    private final List<String> values = new ArrayList<>();
    
    public int encode(String value) {
        return dictionary.computeIfAbsent(value, v -> {
            int id = values.size();
            values.add(v);
            return id;
        });
    }
}
```

## Storage Engine Concepts

### 1. ACID Properties in Distributed Systems

#### Atomicity in Iceberg
```java
// Transaction implementation
public class BaseTransaction implements Transaction {
    
    private final List<PendingUpdate<?>> updates = new ArrayList<>();
    private final TableOperations ops;
    
    @Override
    public void commitTransaction() {
        TableMetadata base = ops.current();
        TableMetadata updated = base;
        
        // Apply all updates atomically
        for (PendingUpdate<?> update : updates) {
            updated = update.apply(updated);
        }
        
        // Atomic commit - either succeeds completely or fails
        ops.commit(base, updated);
    }
}
```

#### Consistency Through Metadata Versioning
```java
// Metadata versioning ensures consistency
public class TableMetadata {
    
    private final int formatVersion;
    private final String uuid;
    private final long lastUpdatedMillis;
    private final int lastColumnId;
    private final Schema schema;
    private final PartitionSpec defaultSpec;
    private final List<Snapshot> snapshots;
    
    // Immutable - creates new version for changes
    public TableMetadata updateSchema(Schema newSchema, int newLastColumnId) {
        return new TableMetadata(
            formatVersion,
            uuid, 
            System.currentTimeMillis(),
            newLastColumnId,
            newSchema,  // Updated schema
            defaultSpec,
            snapshots
        );
    }
}
```

### 2. Optimistic Concurrency Control

#### Implementation Details
```java
// Optimistic concurrency in BaseTableOperations
public class BaseTableOperations implements TableOperations {
    
    @Override
    public TableMetadata commit(TableMetadata base, TableMetadata metadata) {
        // Check if base is still current
        TableMetadata current = current();
        if (!base.metadataFileLocation().equals(current.metadataFileLocation())) {
            throw new CommitFailedException("Concurrent modification detected");
        }
        
        // Write new metadata file
        String newLocation = writeNewMetadata(metadata);
        
        // Atomic pointer update
        if (!updateMetadataLocation(base.metadataFileLocation(), newLocation)) {
            throw new CommitFailedException("Failed to update metadata pointer");
        }
        
        return loadMetadata(newLocation);
    }
}
```

### 3. Snapshot Isolation

#### Snapshot Creation Process
```java
// Snapshot creation in Iceberg
public class SnapshotProducer<T extends SnapshotUpdate<T>> {
    
    protected Snapshot apply(TableMetadata base) {
        long snapshotId = snapshotIdGenerator.generateId();
        
        // Collect all manifest files
        List<ManifestFile> manifests = new ArrayList<>();
        manifests.addAll(base.currentSnapshot().allManifests());
        manifests.addAll(newManifests);
        
        // Create new snapshot
        return new BaseSnapshot(
            snapshotId,
            base.currentSnapshot().snapshotId(), // parent
            System.currentTimeMillis(),
            operation(),
            summary(),
            writeManifestList(manifests)
        );
    }
}
```

## Iceberg Architecture Deep Dive

### 1. Metadata Layer Architecture

#### Metadata File Structure
```java
// TableMetadata.java - Core metadata structure
public class TableMetadata implements Serializable {
    
    // Version information
    private final int formatVersion;
    private final String uuid;
    
    // Schema evolution
    private final Schema schema;
    private final int lastColumnId;
    private final List<HistoryEntry> schemaHistory;
    
    // Partitioning evolution  
    private final PartitionSpec defaultSpec;
    private final int lastAssignedPartitionId;
    private final List<PartitionSpec> specs;
    
    // Snapshot management
    private final long currentSnapshotId;
    private final List<Snapshot> snapshots;
    private final Map<String, SnapshotRef> refs;
    
    // Properties and statistics
    private final Map<String, String> properties;
    private final long lastUpdatedMillis;
    private final List<MetadataLogEntry> metadataLog;
}
```

#### Manifest System
```java
// ManifestFile.java - Manifest metadata
public interface ManifestFile {
    String path();
    long length();
    int specId();
    ManifestContent content();  // DATA or DELETES
    Long snapshotId();
    Integer addedFilesCount();
    Long addedRowsCount();
    Integer existingFilesCount();
    Long existingRowsCount();
    Integer deletedFilesCount();
    Long deletedRowsCount();
    List<PartitionFieldSummary> partitions();
}

// ManifestEntry.java - Individual file entries
public class ManifestEntry<F extends ContentFile<F>> {
    private Status status;  // ADDED, EXISTING, DELETED
    private Long snapshotId;
    private F file;
    
    public enum Status {
        EXISTING(0),
        ADDED(1), 
        DELETED(2);
    }
}
```

### 2. File Organization Strategy

#### Partition Evolution Implementation
```java
// PartitionSpec.java - Partition specification
public class PartitionSpec implements Serializable {
    
    private final Schema schema;
    private final int specId;
    private final List<PartitionField> fields;
    private final transient Map<Integer, PartitionField> fieldsBySourceId;
    
    // Transform functions for partitioning
    public static class PartitionField implements Serializable {
        private final int sourceId;     // Source column ID
        private final int fieldId;      // Partition field ID  
        private final String name;      // Partition field name
        private final Transform<?, ?> transform;  // Transform function
    }
}

// Transform examples
public class Transforms {
    
    // Identity transform: partition by exact value
    public static <T> Transform<T, T> identity(Type type) {
        return new Identity<>(type);
    }
    
    // Bucket transform: hash-based partitioning
    public static <T> Transform<T, Integer> bucket(Type type, int numBuckets) {
        return new Bucket<>(type, numBuckets);
    }
    
    // Truncate transform: truncate strings/decimals
    public static <T> Transform<T, T> truncate(Type type, int width) {
        return new Truncate<>(type, width);
    }
    
    // Date transforms
    public static Transform<Integer, Integer> year() {
        return Years.get();
    }
    
    public static Transform<Integer, Integer> month() {
        return Months.get();
    }
    
    public static Transform<Integer, Integer> day() {
        return Days.get();
    }
}
```
### 3. Query Planning and Execution

#### File Pruning Logic
```java
// ManifestEvaluator.java - Manifest-level filtering
public class ManifestEvaluator {
    
    private final Schema schema;
    private final Expression expr;
    private final boolean caseSensitive;
    
    public boolean eval(ManifestFile manifest) {
        if (manifest.partitions() == null || manifest.partitions().isEmpty()) {
            return true; // Cannot prune without partition data
        }
        
        // Evaluate expression against partition bounds
        for (PartitionFieldSummary partition : manifest.partitions()) {
            if (!evaluatePartition(partition)) {
                return false; // Can prune this manifest
            }
        }
        
        return true; // Cannot prune
    }
}

// InclusiveMetricsEvaluator.java - File-level filtering  
public class InclusiveMetricsEvaluator {
    
    public boolean eval(DataFile file) {
        // Use column statistics for pruning
        Map<Integer, Long> valueCounts = file.valueCounts();
        Map<Integer, Long> nullValueCounts = file.nullValueCounts();
        Map<Integer, ByteBuffer> lowerBounds = file.lowerBounds();
        Map<Integer, ByteBuffer> upperBounds = file.upperBounds();
        
        return new InclusiveMetricsEvaluator(schema, expr, caseSensitive)
            .eval(valueCounts, nullValueCounts, lowerBounds, upperBounds);
    }
}
```

## Core Components

### 1. Catalog Implementations

#### Hive Metastore Catalog
```java
// HiveCatalog.java - Integration with Hive Metastore
public class HiveCatalog extends BaseMetastoreCatalog {
    
    @Override
    public Table loadTable(TableIdentifier identifier) {
        // Load table from Hive Metastore
        org.apache.hadoop.hive.metastore.api.Table hiveTable = 
            metastore.getTable(identifier.namespace().level(0), identifier.name());
            
        // Extract Iceberg metadata location
        String metadataLocation = hiveTable.getParameters().get(METADATA_LOCATION_PROP);
        
        // Load Iceberg table from metadata
        TableOperations ops = newTableOps(identifier);
        return new BaseTable(ops, identifier.toString());
    }
    
    @Override
    protected TableOperations newTableOps(TableIdentifier tableIdentifier) {
        return new HiveTableOperations(conf, metastore, fileIO, catalogName, tableIdentifier);
    }
}
```

#### REST Catalog
```java
// RESTCatalog.java - HTTP-based catalog
public class RESTCatalog implements Catalog {
    
    private RESTClient client;
    
    @Override
    public Table loadTable(TableIdentifier identifier) {
        // HTTP GET request to load table metadata
        LoadTableResponse response = client.get(
            paths.table(identifier),
            LoadTableResponse.class,
            headers(),
            ErrorHandlers.tableErrorHandler()
        );
        
        return new BaseTable(
            newTableOps(identifier, response.tableMetadata()),
            identifier.toString()
        );
    }
}
```

### 2. FileIO Implementations

#### S3 FileIO
```java
// S3FileIO.java - AWS S3 integration
public class S3FileIO implements FileIO {
    
    private AmazonS3 s3;
    private S3Configuration s3Config;
    
    @Override
    public InputFile newInputFile(String path) {
        return new S3InputFile(s3, S3URI.create(path), s3Config);
    }
    
    @Override
    public OutputFile newOutputFile(String path) {
        return new S3OutputFile(s3, S3URI.create(path), s3Config);
    }
    
    @Override
    public void deleteFile(String path) {
        S3URI s3Uri = S3URI.create(path);
        s3.deleteObject(s3Uri.bucket(), s3Uri.key());
    }
}

// S3InputFile.java - S3 input file implementation
public class S3InputFile implements InputFile {
    
    @Override
    public SeekableInputStream newStream() {
        return new S3SeekableInputStream(s3, uri, s3Config);
    }
    
    @Override
    public long getLength() {
        ObjectMetadata metadata = s3.getObjectMetadata(uri.bucket(), uri.key());
        return metadata.getContentLength();
    }
}
```

### 3. Engine Integrations

#### Spark Integration Architecture
```java
// SparkTable.java - Spark DataSource V2 integration
public class SparkTable implements Table, SupportsRead, SupportsWrite, SupportsDelete {
    
    private final org.apache.iceberg.Table icebergTable;
    private final boolean refreshEagerly;
    
    @Override
    public ScanBuilder newScanBuilder(CaseInsensitiveStringMap options) {
        return new SparkScanBuilder(sparkSession, icebergTable, options);
    }
    
    @Override
    public WriteBuilder newWriteBuilder(LogicalWriteInfo info) {
        return new SparkWriteBuilder(sparkSession, icebergTable, info);
    }
}

// SparkScanBuilder.java - Query planning integration
public class SparkScanBuilder implements ScanBuilder, SupportsPushDownFilters, SupportsPushDownRequiredColumns {
    
    @Override
    public Filter[] pushFilters(Filter[] filters) {
        List<Expression> expressions = new ArrayList<>();
        List<Filter> pushed = new ArrayList<>();
        
        for (Filter filter : filters) {
            Expression expr = SparkFilters.convert(filter);
            if (expr != null) {
                expressions.add(expr);
                pushed.add(filter);
            }
        }
        
        // Apply filters to Iceberg scan
        this.scan = scan.filter(Expressions.and(expressions));
        
        return pushed.toArray(new Filter[0]);
    }
}
```

## Development Environment Setup

### 1. Building from Source

```bash
# Clone the repository
git clone https://github.com/apache/iceberg.git
cd iceberg

# Build with Gradle
./gradlew build

# Run tests
./gradlew test

# Build specific modules
./gradlew :iceberg-core:build
./gradlew :iceberg-spark:iceberg-spark-3.4_2.12:build
```

### 2. IDE Setup

#### IntelliJ IDEA Configuration
```gradle
// build.gradle - IDE integration
apply plugin: 'idea'

idea {
    module {
        downloadJavadoc = true
        downloadSources = true
    }
}

// Import Gradle project in IntelliJ
// File -> New -> Project from Existing Sources -> Select build.gradle
```

#### Code Style Configuration
```xml
<!-- .editorconfig -->
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true

[*.java]
indent_size = 2
max_line_length = 100
```

### 3. Testing Framework

#### Unit Testing Structure
```java
// Example test class structure
public class TestTableMetadata {
    
    private static final Schema SCHEMA = new Schema(
        required(1, "id", Types.LongType.get()),
        optional(2, "data", Types.StringType.get())
    );
    
    @Test
    public void testSchemaEvolution() {
        TableMetadata metadata = TableMetadata.newTableMetadata(
            SCHEMA,
            PartitionSpec.unpartitioned(),
            "file:/tmp/test",
            ImmutableMap.of()
        );
        
        Schema newSchema = new Schema(
            required(1, "id", Types.LongType.get()),
            optional(2, "data", Types.StringType.get()),
            optional(3, "new_column", Types.IntegerType.get())
        );
        
        TableMetadata updated = metadata.updateSchema(newSchema, 3);
        
        Assert.assertEquals("Schema should be updated", newSchema.asStruct(), updated.schema().asStruct());
        Assert.assertEquals("Last column ID should be updated", 3, updated.lastColumnId());
    }
}
```

#### Integration Testing
```java
// TestBase.java - Common test utilities
public abstract class TestBase {
    
    protected static final Configuration CONF = new Configuration();
    protected FileIO fileIO;
    protected String tableLocation;
    
    @Before
    public void setupTable() {
        this.fileIO = new HadoopFileIO(CONF);
        this.tableLocation = temp.newFolder().toURI().toString();
    }
    
    protected Table createTable(Schema schema, PartitionSpec spec) {
        HadoopCatalog catalog = new HadoopCatalog(CONF, tableLocation);
        return catalog.createTable(
            TableIdentifier.of("test_table"),
            schema,
            spec
        );
    }
}
```

## Contributing Guidelines

### 1. Code Organization

#### Module Structure
```
iceberg/
├── api/                    # Public API interfaces
├── core/                   # Core implementation
├── data/                   # Data access utilities
├── parquet/               # Parquet format support
├── orc/                   # ORC format support  
├── hive-metastore/        # Hive catalog integration
├── spark/                 # Spark engine integration
│   ├── v3.3/             # Spark 3.3 support
│   ├── v3.4/             # Spark 3.4 support
│   └── v3.5/             # Spark 3.5 support
├── flink/                 # Flink engine integration
├── aws/                   # AWS integrations (S3, Glue)
├── azure/                 # Azure integrations
├── gcp/                   # Google Cloud integrations
└── open-api/             # REST API specifications
```

### 2. Development Workflow

#### Creating a Feature
```bash
# Create feature branch
git checkout -b feature/my-new-feature

# Make changes and test
./gradlew test

# Run specific tests
./gradlew :iceberg-core:test --tests "*TestTableMetadata*"

# Check code style
./gradlew checkstyleMain checkstyleTest

# Build documentation
./gradlew javadoc
```

#### Pull Request Process
```markdown
## Pull Request Template

### Summary
Brief description of changes

### Type of Change
- [ ] Bug fix
- [ ] New feature  
- [ ] Breaking change
- [ ] Documentation update

### Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing performed

### Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No new warnings introduced
```

### 3. Key Areas for Contribution

#### Performance Optimizations
```java
// Example: Manifest caching optimization
public class CachingManifestReader {
    
    private final Cache<String, ManifestFile> manifestCache;
    
    public CloseableIterable<ManifestEntry<DataFile>> read(ManifestFile manifest) {
        // Check cache first
        ManifestFile cached = manifestCache.getIfPresent(manifest.path());
        if (cached != null && cached.length() == manifest.length()) {
            return readFromCache(cached);
        }
        
        // Read and cache
        CloseableIterable<ManifestEntry<DataFile>> entries = readManifest(manifest);
        manifestCache.put(manifest.path(), manifest);
        return entries;
    }
}
```

#### New Engine Integrations
```java
// Template for new engine integration
public class NewEngineTable implements EngineTable {
    
    private final org.apache.iceberg.Table icebergTable;
    
    @Override
    public EngineQueryPlan planQuery(EngineQuery query) {
        // Convert engine query to Iceberg scan
        TableScan scan = icebergTable.newScan();
        
        // Apply filters
        if (query.hasFilters()) {
            Expression filter = convertFilters(query.getFilters());
            scan = scan.filter(filter);
        }
        
        // Apply projections
        if (query.hasProjections()) {
            Schema projected = convertProjections(query.getProjections());
            scan = scan.select(projected.columns());
        }
        
        return new EngineQueryPlan(scan.planFiles());
    }
}
```

This developer guide provides the foundation needed to understand Iceberg's internals and start contributing effectively to the project. The next sections would cover specific contribution areas and advanced topics.
## Advanced Development Topics

### 1. Expression System Deep Dive

#### Expression Tree Structure
```java
// Expression.java - Base expression interface
public interface Expression extends Serializable {
    
    enum Operation {
        TRUE, FALSE, NOT, AND, OR,
        IS_NULL, NOT_NULL, IS_NAN, NOT_NAN,
        LT, LT_EQ, GT, GT_EQ, EQ, NOT_EQ,
        IN, NOT_IN, STARTS_WITH, NOT_STARTS_WITH
    }
    
    Operation op();
    List<Expression> children();
    
    default <R> R visit(ExpressionVisitor<R> visitor) {
        switch (op()) {
            case TRUE:
                return visitor.alwaysTrue();
            case FALSE:
                return visitor.alwaysFalse();
            case NOT:
                return visitor.not(children().get(0).visit(visitor));
            case AND:
                return visitor.and(
                    children().get(0).visit(visitor),
                    children().get(1).visit(visitor)
                );
            // ... other operations
        }
    }
}

// Predicate implementation example
public class BoundPredicate<T> implements Predicate<T> {
    
    private final Operation op;
    private final BoundTerm<T> term;
    private final Literal<T> literal;
    
    @Override
    public boolean test(StructLike struct) {
        T value = term.eval(struct);
        
        switch (op) {
            case LT:
                return literal.comparator().compare(value, literal.value()) < 0;
            case LT_EQ:
                return literal.comparator().compare(value, literal.value()) <= 0;
            case GT:
                return literal.comparator().compare(value, literal.value()) > 0;
            case GT_EQ:
                return literal.comparator().compare(value, literal.value()) >= 0;
            case EQ:
                return Objects.equals(value, literal.value());
            case NOT_EQ:
                return !Objects.equals(value, literal.value());
            default:
                throw new UnsupportedOperationException("Operation not supported: " + op);
        }
    }
}
```

### 2. Statistics and Metrics System

#### Column Statistics Implementation
```java
// Metrics.java - File-level statistics
public class Metrics implements Serializable {
    
    private final Long recordCount;
    private final Map<Integer, Long> columnSizes;
    private final Map<Integer, Long> valueCounts;
    private final Map<Integer, Long> nullValueCounts;
    private final Map<Integer, Long> nanValueCounts;
    private final Map<Integer, ByteBuffer> lowerBounds;
    private final Map<Integer, ByteBuffer> upperBounds;
    
    // Statistics collection during write
    public static class MetricsCollector {
        
        private long recordCount = 0;
        private final Map<Integer, ColumnMetrics> columnMetrics = new HashMap<>();
        
        public void update(StructLike row, Schema schema) {
            recordCount++;
            
            for (Types.NestedField field : schema.columns()) {
                int id = field.fieldId();
                Object value = row.get(schema.idToPosition().get(id), Object.class);
                
                ColumnMetrics metrics = columnMetrics.computeIfAbsent(id, 
                    k -> new ColumnMetrics(field.type()));
                metrics.update(value);
            }
        }
        
        public Metrics build() {
            Map<Integer, Long> valueCounts = new HashMap<>();
            Map<Integer, Long> nullCounts = new HashMap<>();
            Map<Integer, ByteBuffer> lowerBounds = new HashMap<>();
            Map<Integer, ByteBuffer> upperBounds = new HashMap<>();
            
            for (Map.Entry<Integer, ColumnMetrics> entry : columnMetrics.entrySet()) {
                int id = entry.getKey();
                ColumnMetrics metrics = entry.getValue();
                
                valueCounts.put(id, metrics.valueCount());
                nullCounts.put(id, metrics.nullCount());
                
                if (metrics.hasNonNullValue()) {
                    lowerBounds.put(id, metrics.lowerBound());
                    upperBounds.put(id, metrics.upperBound());
                }
            }
            
            return new Metrics(recordCount, null, valueCounts, nullCounts, null, lowerBounds, upperBounds);
        }
    }
}
```

### 3. Schema Evolution Engine

#### Schema Compatibility Checking
```java
// SchemaEvolution.java - Schema evolution logic
public class SchemaEvolution {
    
    private final Schema currentSchema;
    private final Schema newSchema;
    private final Map<String, String> renames;
    
    public void checkCompatibility() {
        // Check for breaking changes
        for (Types.NestedField currentField : currentSchema.columns()) {
            Types.NestedField newField = newSchema.findField(currentField.fieldId());
            
            if (newField == null) {
                if (currentField.isRequired()) {
                    throw new ValidationException(
                        "Cannot delete required field: " + currentField.name());
                }
                continue; // Optional field deletion is allowed
            }
            
            // Check type compatibility
            if (!TypeUtil.isPromotionAllowed(currentField.type(), newField.type())) {
                throw new ValidationException(
                    String.format("Cannot change field type from %s to %s for field %s",
                        currentField.type(), newField.type(), currentField.name()));
            }
            
            // Check nullability
            if (currentField.isOptional() && newField.isRequired()) {
                throw new ValidationException(
                    "Cannot change optional field to required: " + currentField.name());
            }
        }
    }
    
    // Type promotion rules
    private static final Map<Type.TypeID, Set<Type.TypeID>> PROMOTIONS = ImmutableMap.of(
        Type.TypeID.INTEGER, ImmutableSet.of(Type.TypeID.LONG),
        Type.TypeID.FLOAT, ImmutableSet.of(Type.TypeID.DOUBLE),
        Type.TypeID.DECIMAL, ImmutableSet.of(Type.TypeID.DECIMAL) // Same scale/precision rules apply
    );
}
```

### 4. Delete File System

#### Position Delete Implementation
```java
// PositionDelete.java - Position-based deletes
public class PositionDelete<T> implements StructLike {
    
    private final CharSequence path;
    private final long position;
    private final T row; // Optional row data for validation
    
    public static <T> PositionDelete<T> create(CharSequence path, long position, T row) {
        return new PositionDelete<>(path, position, row);
    }
    
    // Used during merge-on-read
    public boolean shouldDelete(CharSequence filePath, long rowPosition) {
        return Objects.equals(path, filePath) && position == rowPosition;
    }
}

// EqualityDelete.java - Equality-based deletes  
public class EqualityDelete implements StructLike {
    
    private final Schema deleteSchema;
    private final StructLike deleteRow;
    
    public boolean shouldDelete(StructLike dataRow, Schema dataSchema) {
        // Compare equality fields
        for (Types.NestedField field : deleteSchema.columns()) {
            int deletePos = deleteSchema.idToPosition().get(field.fieldId());
            int dataPos = dataSchema.idToPosition().get(field.fieldId());
            
            Object deleteValue = deleteRow.get(deletePos, Object.class);
            Object dataValue = dataRow.get(dataPos, Object.class);
            
            if (!Objects.equals(deleteValue, dataValue)) {
                return false;
            }
        }
        return true;
    }
}
```

## Key Contribution Areas

### 1. Performance Optimizations

#### Manifest Caching
```java
// Contribution opportunity: Implement intelligent manifest caching
public class AdaptiveManifestCache {
    
    private final Cache<String, ManifestFile> hotCache;  // Frequently accessed
    private final Cache<String, ManifestFile> coldCache; // Infrequently accessed
    private final AccessTracker accessTracker;
    
    public ManifestFile get(String path) {
        // Track access patterns
        accessTracker.recordAccess(path);
        
        // Check hot cache first
        ManifestFile manifest = hotCache.getIfPresent(path);
        if (manifest != null) {
            return manifest;
        }
        
        // Check cold cache
        manifest = coldCache.getIfPresent(path);
        if (manifest != null) {
            // Promote to hot cache if frequently accessed
            if (accessTracker.isHot(path)) {
                hotCache.put(path, manifest);
                coldCache.invalidate(path);
            }
            return manifest;
        }
        
        // Load from storage
        return loadAndCache(path);
    }
}
```

#### Vectorized Expression Evaluation
```java
// Contribution opportunity: SIMD-optimized expression evaluation
public class VectorizedExpressionEvaluator {
    
    public BitSet evaluateFilter(Expression expr, ColumnarBatch batch) {
        if (expr instanceof BoundPredicate) {
            return evaluatePredicate((BoundPredicate<?>) expr, batch);
        } else if (expr instanceof And) {
            BitSet left = evaluateFilter(expr.children().get(0), batch);
            BitSet right = evaluateFilter(expr.children().get(1), batch);
            left.and(right);
            return left;
        }
        // ... other expression types
        
        return new BitSet(); // Fallback
    }
    
    private BitSet evaluatePredicate(BoundPredicate<?> predicate, ColumnarBatch batch) {
        // Use vectorized operations for common predicates
        switch (predicate.op()) {
            case GT:
                return evaluateGreaterThan(predicate, batch);
            case EQ:
                return evaluateEquals(predicate, batch);
            // ... other operations
        }
        return new BitSet();
    }
}
```

### 2. New Engine Integrations

#### Presto/Trino Enhancements
```java
// Contribution opportunity: Advanced Trino optimizations
public class IcebergDynamicFiltering {
    
    public ConnectorSplitSource getSplitsWithDynamicFiltering(
            ConnectorTableHandle table,
            Constraint constraint,
            DynamicFilter dynamicFilter) {
        
        IcebergTableHandle icebergTable = (IcebergTableHandle) table;
        
        // Wait for dynamic filters to be available
        CompletableFuture<Set<ColumnHandle>> filtersFuture = 
            dynamicFilter.isAwaitable() ? 
                dynamicFilter.isBlocked().thenApply(ignored -> dynamicFilter.getColumnsCovered()) :
                CompletableFuture.completedFuture(dynamicFilter.getColumnsCovered());
        
        return new IcebergSplitSource(icebergTable, constraint, filtersFuture);
    }
}
```

### 3. Cloud Storage Optimizations

#### Multi-Cloud FileIO
```java
// Contribution opportunity: Unified multi-cloud interface
public class MultiCloudFileIO implements FileIO {
    
    private final Map<String, FileIO> delegates;
    
    public MultiCloudFileIO() {
        this.delegates = ImmutableMap.of(
            "s3", new S3FileIO(),
            "gs", new GCSFileIO(), 
            "abfs", new AzureFileIO(),
            "hdfs", new HadoopFileIO()
        );
    }
    
    @Override
    public InputFile newInputFile(String path) {
        String scheme = URI.create(path).getScheme();
        FileIO delegate = delegates.get(scheme);
        
        if (delegate == null) {
            throw new UnsupportedOperationException("Unsupported scheme: " + scheme);
        }
        
        return new TrackedInputFile(delegate.newInputFile(path), path);
    }
}
```

### 4. Monitoring and Observability

#### Metrics Collection Framework
```java
// Contribution opportunity: Comprehensive metrics system
public class IcebergMetrics {
    
    private final MeterRegistry meterRegistry;
    
    // Operation metrics
    private final Counter scanOperations;
    private final Counter writeOperations;
    private final Timer scanDuration;
    private final Timer writeDuration;
    
    // Performance metrics
    private final Gauge manifestCacheHitRate;
    private final Gauge filePruningEfficiency;
    private final Counter filesScanned;
    private final Counter filesPruned;
    
    public void recordScan(TableScan scan, Duration duration, long filesScanned, long filesPruned) {
        scanOperations.increment();
        scanDuration.record(duration);
        this.filesScanned.increment(filesScanned);
        this.filesPruned.increment(filesPruned);
        
        // Calculate pruning efficiency
        double efficiency = filesPruned / (double) (filesScanned + filesPruned);
        filePruningEfficiency.set(efficiency);
    }
}
```

## Getting Started with Contributions

### 1. Good First Issues

#### Documentation Improvements
- Add code examples to existing documentation
- Improve error messages with better context
- Add performance tuning guides

#### Test Coverage
- Add unit tests for edge cases
- Improve integration test coverage
- Add performance benchmarks

#### Bug Fixes
- Fix memory leaks in long-running operations
- Improve error handling in edge cases
- Fix compatibility issues with new engine versions

### 2. Development Best Practices

#### Code Quality Guidelines
```java
// Follow Iceberg coding standards
public class ExampleClass {
    
    // Use meaningful variable names
    private final Map<Integer, PartitionField> fieldsBySourceId;
    
    // Add comprehensive javadoc
    /**
     * Creates a new partition spec with the given fields.
     * 
     * @param schema the table schema
     * @param fields the partition fields
     * @return a new partition spec
     * @throws ValidationException if fields are invalid
     */
    public static PartitionSpec create(Schema schema, List<PartitionField> fields) {
        // Validate inputs
        Preconditions.checkNotNull(schema, "Schema cannot be null");
        Preconditions.checkNotNull(fields, "Fields cannot be null");
        
        // Implementation...
        return new PartitionSpec(schema, fields);
    }
}
```

#### Testing Strategy
```java
// Write comprehensive tests
@Test
public void testSchemaEvolutionWithNestedStructs() {
    // Given: Table with nested struct
    Schema originalSchema = new Schema(
        required(1, "id", Types.LongType.get()),
        optional(2, "person", Types.StructType.of(
            required(3, "name", Types.StringType.get()),
            optional(4, "age", Types.IntegerType.get())
        ))
    );
    
    // When: Add field to nested struct
    Schema evolvedSchema = new Schema(
        required(1, "id", Types.LongType.get()),
        optional(2, "person", Types.StructType.of(
            required(3, "name", Types.StringType.get()),
            optional(4, "age", Types.IntegerType.get()),
            optional(5, "email", Types.StringType.get()) // New field
        ))
    );
    
    // Then: Evolution should succeed
    TableMetadata metadata = createTableMetadata(originalSchema);
    TableMetadata evolved = metadata.updateSchema(evolvedSchema, 5);
    
    assertThat(evolved.schema()).isEqualTo(evolvedSchema);
    assertThat(evolved.lastColumnId()).isEqualTo(5);
}
```

This comprehensive developer guide provides everything needed to understand Iceberg's internals and start contributing effectively to the project. Focus on understanding the core concepts first, then dive into specific areas that interest you most.
