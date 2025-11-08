# Apache Iceberg: Advanced Techniques and Optimizations

## Table of Contents
1. [Copy-on-Write (COW) Strategy](#copy-on-write-cow-strategy)
2. [Vectorized Processing](#vectorized-processing)
3. [Predicate Pushdown](#predicate-pushdown)
4. [Partition Pruning](#partition-pruning)
5. [File Pruning](#file-pruning)
6. [Metadata Caching](#metadata-caching)
7. [Lazy Evaluation](#lazy-evaluation)
8. [Bloom Filters](#bloom-filters)
9. [Delta Encoding](#delta-encoding)
10. [Compression Techniques](#compression-techniques)

## Copy-on-Write (COW) Strategy

### Concept Overview
Copy-on-Write is a fundamental technique in Iceberg where data structures are immutable, and modifications create new copies rather than modifying existing data.

### Implementation in Metadata
```java
// TableMetadata.java - Immutable metadata with COW
public class TableMetadata implements Serializable {
    
    private final Schema schema;
    private final List<Snapshot> snapshots;
    private final Map<String, String> properties;
    
    // All fields are final and immutable
    
    // COW operation: creates new instance instead of modifying
    public TableMetadata updateSchema(Schema newSchema, int newLastColumnId) {
        return new TableMetadata(
            formatVersion,
            uuid,
            System.currentTimeMillis(),
            newLastColumnId,
            newSchema,           // New schema
            defaultSpec,
            snapshots,          // Reused (immutable)
            refs,
            properties,         // Reused (immutable)
            currentSnapshotId,
            metadataLog
        );
    }
    
    // COW for adding snapshots
    public TableMetadata addSnapshot(Snapshot snapshot) {
        List<Snapshot> newSnapshots = ImmutableList.<Snapshot>builder()
            .addAll(snapshots)
            .add(snapshot)
            .build();
            
        return new TableMetadata(
            formatVersion, uuid, System.currentTimeMillis(),
            lastColumnId, schema, defaultSpec,
            newSnapshots,        // New list with added snapshot
            refs, properties, snapshot.snapshotId(), metadataLog
        );
    }
}
```

### Benefits of COW in Iceberg
```java
// Thread-safe concurrent access
public class ConcurrentTableAccess {
    
    public void demonstrateCOWSafety() {
        Table table = catalog.loadTable(TableIdentifier.of("db", "table"));
        
        // Thread 1: Reading metadata
        CompletableFuture<Void> reader = CompletableFuture.runAsync(() -> {
            TableMetadata metadata = ((BaseTable) table).operations().current();
            // This snapshot of metadata never changes, even if table is updated
            processMetadata(metadata);
        });
        
        // Thread 2: Updating schema
        CompletableFuture<Void> writer = CompletableFuture.runAsync(() -> {
            table.updateSchema()
                .addColumn("new_column", Types.StringType.get())
                .commit();
            // Creates new metadata, doesn't affect reader's view
        });
        
        // Both operations are safe and isolated
        CompletableFuture.allOf(reader, writer).join();
    }
}
```

### COW in Snapshot Management
```java
// BaseSnapshot.java - Immutable snapshot implementation
public class BaseSnapshot implements Snapshot {
    
    private final long snapshotId;
    private final Long parentId;
    private final List<ManifestFile> allManifests;  // Immutable list
    
    // Snapshots are never modified after creation
    public BaseSnapshot(long snapshotId, Long parentId, long timestampMillis,
                       String operation, Map<String, String> summary,
                       String manifestListLocation) {
        this.snapshotId = snapshotId;
        this.parentId = parentId;
        this.timestampMillis = timestampMillis;
        this.operation = operation;
        this.summary = ImmutableMap.copyOf(summary);  // Defensive copy
        this.manifestListLocation = manifestListLocation;
        this.allManifests = null; // Loaded lazily, but immutable once loaded
    }
}
```

## Vectorized Processing

### SIMD Operations in File Reading
```java
// VectorizedParquetReader.java - Vectorized Parquet processing
public class VectorizedParquetReader {
    
    private final VectorizedColumnReader[] columnReaders;
    private final int batchSize;
    
    public ColumnarBatch nextBatch() {
        ColumnarBatch batch = ColumnarBatch.allocate(schema, batchSize);
        
        // Read all columns in vectorized fashion
        for (int i = 0; i < columnReaders.length; i++) {
            ColumnVector vector = batch.column(i);
            columnReaders[i].readBatch(batchSize, vector);
        }
        
        return batch;
    }
}

// Vectorized filter evaluation
public class VectorizedFilterEvaluator {
    
    public BitSet evaluateFilter(Expression filter, ColumnarBatch batch) {
        if (filter instanceof BoundPredicate) {
            return evaluatePredicate((BoundPredicate<?>) filter, batch);
        }
        
        // Vectorized AND operation
        if (filter instanceof And) {
            BitSet left = evaluateFilter(filter.children().get(0), batch);
            BitSet right = evaluateFilter(filter.children().get(1), batch);
            left.and(right);  // Bitwise AND operation
            return left;
        }
        
        return new BitSet(batch.numRows());
    }
    
    private BitSet evaluateGreaterThan(BoundPredicate<?> predicate, ColumnarBatch batch) {
        ColumnVector column = batch.column(predicate.term().ref().fieldId());
        Object threshold = predicate.literal().value();
        BitSet result = new BitSet(batch.numRows());
        
        // Vectorized comparison (processes multiple values at once)
        if (column instanceof IntegerColumnVector) {
            IntegerColumnVector intVector = (IntegerColumnVector) column;
            int thresholdInt = (Integer) threshold;
            
            // SIMD-optimized comparison
            for (int i = 0; i < batch.numRows(); i += 8) {
                // Process 8 integers at once using SIMD
                compareGreaterThanSIMD(intVector, i, thresholdInt, result);
            }
        }
        
        return result;
    }
    
    // Native method using SIMD instructions
    private native void compareGreaterThanSIMD(IntegerColumnVector vector, 
                                              int offset, int threshold, BitSet result);
}
```

### Vectorized Aggregations
```java
// VectorizedAggregator.java - SIMD aggregations
public class VectorizedAggregator {
    
    public long sumIntegers(IntegerColumnVector vector) {
        long sum = 0;
        int length = vector.length();
        
        // Process 8 integers at once using AVX2
        int i = 0;
        for (; i <= length - 8; i += 8) {
            sum += sumEightIntegers(vector, i);  // SIMD operation
        }
        
        // Handle remaining elements
        for (; i < length; i++) {
            sum += vector.getInt(i);
        }
        
        return sum;
    }
    
    // AVX2 implementation for summing 8 integers
    private native long sumEightIntegers(IntegerColumnVector vector, int offset);
}
```

## Predicate Pushdown

### Expression Tree Transformation
```java
// Binder.java - Binds expressions to schema
public class Binder {
    
    public static Expression bind(Schema schema, Expression expr, boolean caseSensitive) {
        return new BindVisitor(schema, caseSensitive).bind(expr);
    }
    
    private static class BindVisitor extends ExpressionVisitors.ExpressionVisitor<Expression> {
        
        @Override
        public Expression predicate(Operation op, Expression term, Expression lit) {
            if (term instanceof UnboundTerm && lit instanceof Literal) {
                UnboundTerm<?> unbound = (UnboundTerm<?>) term;
                
                // Bind term to schema field
                int fieldId = schema.findField(unbound.ref().name()).fieldId();
                BoundTerm<?> boundTerm = new BoundReference<>(schema, fieldId);
                
                return new BoundPredicate<>(op, boundTerm, (Literal<?>) lit);
            }
            
            return super.predicate(op, term, lit);
        }
    }
}

// Predicate pushdown to file level
public class FilePredicatePushdown {
    
    public boolean canSkipFile(DataFile file, Expression predicate) {
        // Use file-level statistics for pushdown
        Map<Integer, ByteBuffer> lowerBounds = file.lowerBounds();
        Map<Integer, ByteBuffer> upperBounds = file.upperBounds();
        Map<Integer, Long> nullCounts = file.nullValueCounts();
        Map<Integer, Long> valueCounts = file.valueCounts();
        
        // Evaluate predicate against file statistics
        return new InclusiveMetricsEvaluator(schema, predicate, caseSensitive)
            .eval(valueCounts, nullCounts, lowerBounds, upperBounds);
    }
}
```

### Multi-Level Pushdown
```java
// ManifestEvaluator.java - Manifest-level pushdown
public class ManifestEvaluator {
    
    public boolean eval(ManifestFile manifest) {
        if (manifest.partitions() == null) {
            return true; // Cannot prune without partition info
        }
        
        // Evaluate against partition bounds
        for (PartitionFieldSummary partition : manifest.partitions()) {
            if (!canIncludePartition(partition)) {
                return false; // Can skip entire manifest
            }
        }
        
        return true;
    }
    
    private boolean canIncludePartition(PartitionFieldSummary partition) {
        // Check if partition bounds overlap with predicate
        ByteBuffer lowerBound = partition.lowerBound();
        ByteBuffer upperBound = partition.upperBound();
        
        // Evaluate predicate against partition bounds
        return evaluatePartitionBounds(lowerBound, upperBound);
    }
}
```

## Partition Pruning

### Partition Spec Evolution
```java
// PartitionSpec.java - Partition specification
public class PartitionSpec implements Serializable {
    
    private final List<PartitionField> fields;
    private final Map<Integer, PartitionField> fieldsBySourceId;
    
    // Partition field with transform
    public static class PartitionField {
        private final int sourceId;      // Source column ID
        private final int fieldId;       // Partition field ID
        private final String name;       // Partition name
        private final Transform<?, ?> transform;  // Transform function
        
        // Apply transform to create partition value
        public <T> Object apply(T sourceValue) {
            return ((Transform<T, ?>) transform).apply(sourceValue);
        }
    }
}

// Partition pruning logic
public class PartitionPruner {
    
    public Set<ManifestFile> pruneManifests(List<ManifestFile> manifests, Expression filter) {
        Set<ManifestFile> prunedManifests = new HashSet<>();
        
        for (ManifestFile manifest : manifests) {
            if (canIncludeManifest(manifest, filter)) {
                prunedManifests.add(manifest);
            }
        }
        
        return prunedManifests;
    }
    
    private boolean canIncludeManifest(ManifestFile manifest, Expression filter) {
        // Transform filter to partition space
        Expression partitionFilter = Projections.inclusive(partitionSpec).project(filter);
        
        // Evaluate against manifest partition bounds
        return new ManifestEvaluator(partitionSpec, partitionFilter, caseSensitive)
            .eval(manifest);
    }
}
```

### Transform-Based Pruning
```java
// Transform implementations for partition pruning
public class Transforms {
    
    // Bucket transform for hash partitioning
    public static class Bucket<T> implements Transform<T, Integer> {
        
        @Override
        public Integer apply(T value) {
            return hash(value) % numBuckets;
        }
        
        @Override
        public boolean canTransform(Type type) {
            return type.isPrimitiveType();
        }
        
        // Pruning: can determine if bucket contains value
        public boolean mightContain(Integer bucketValue, T filterValue) {
            return apply(filterValue).equals(bucketValue);
        }
    }
    
    // Truncate transform for string/decimal partitioning
    public static class Truncate<T> implements Transform<T, T> {
        
        @Override
        public T apply(T value) {
            if (value instanceof CharSequence) {
                CharSequence str = (CharSequence) value;
                return (T) str.subSequence(0, Math.min(width, str.length()));
            }
            return value;
        }
        
        // Pruning: check if truncated range overlaps
        public boolean rangeOverlaps(T partitionValue, T filterMin, T filterMax) {
            T truncatedMin = apply(filterMin);
            T truncatedMax = apply(filterMax);
            
            return comparator.compare(partitionValue, truncatedMax) <= 0 &&
                   comparator.compare(partitionValue, truncatedMin) >= 0;
        }
    }
}
```
