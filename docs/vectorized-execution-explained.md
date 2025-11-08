# Vectorized Execution: Why It's 10x Faster Than Row-Based Processing

## Overview

**Vectorized execution** means processing data in **batches (vectors)** rather than one row at a time, leveraging modern CPU capabilities for dramatic performance improvements. This approach can deliver 5-20x performance gains over traditional row-based processing.

## Row-Based vs Vectorized Processing

### Row-Based Processing (Traditional)
```java
// Process one row at a time
for (Row row : dataset) {
    int id = row.getInt("id");
    String name = row.getString("name");
    double salary = row.getDouble("salary");
    
    // Apply filter: salary > 50000
    if (salary > 50000) {
        result.add(new Row(id, name, salary * 1.1)); // 10% raise
    }
}
```

**Characteristics:**
- Processes one record at a time
- High function call overhead
- Poor CPU cache utilization
- Unpredictable memory access patterns

### Vectorized Processing
```java
// Process entire columns at once
IntVector ids = batch.getIntVector("id");
StringVector names = batch.getStringVector("name"); 
DoubleVector salaries = batch.getDoubleVector("salary");

// Vectorized operations on entire arrays
BooleanVector filter = salaries.greaterThan(50000.0);
DoubleVector newSalaries = salaries.multiply(1.1, filter);
```

**Characteristics:**
- Processes batches of 1000+ records simultaneously
- Minimal function call overhead
- Optimal CPU cache utilization
- Sequential memory access patterns

## Why Vectorized Execution is 10x Faster

### 1. CPU Cache Efficiency

#### Memory Layout Comparison
```
Row-based (AoS - Array of Structures):
[id1|name1|salary1][id2|name2|salary2][id3|name3|salary3]...
- Random memory access
- Poor cache locality
- Frequent cache misses

Vectorized (SoA - Structure of Arrays):  
IDs:      [id1][id2][id3][id4]...
Names:    [name1][name2][name3][name4]...
Salaries: [salary1][salary2][salary3][salary4]...
- Sequential memory access
- Excellent cache locality
- Minimal cache misses
```

**Performance Impact:**
- **Row-based**: 60-80% cache miss rate
- **Vectorized**: 5-15% cache miss rate
- **Speedup**: 3-5x improvement

### 2. SIMD Instructions (Single Instruction, Multiple Data)

```assembly
; Row-based: One operation at a time
LOAD R1, [salary1]
CMP R1, 50000
JLE skip1
MUL R1, 1.1
STORE [result1], R1

; Vectorized: Multiple operations simultaneously
LOAD V1, [salary_array]     ; Load 8 salaries at once
VCMP V2, V1, 50000_vector   ; Compare all 8 simultaneously  
VMUL V3, V1, 1.1_vector     ; Multiply all 8 simultaneously
STORE [result_array], V3    ; Store all 8 results
```

**Modern CPU Capabilities:**
- **AVX-512**: Process 16 floats or 8 doubles simultaneously
- **AVX2**: Process 8 floats or 4 doubles simultaneously
- **SSE**: Process 4 floats or 2 doubles simultaneously

**Performance Impact:**
- **Theoretical speedup**: 2-16x (depending on CPU and data type)
- **Practical speedup**: 2-4x (due to memory bandwidth limits)

### 3. Reduced Function Call Overhead

```java
// Row-based: Million function calls
for (int i = 0; i < 1_000_000; i++) {
    processRow(dataset.getRow(i)); // 1M function calls
}

// Vectorized: Thousand function calls  
for (int batch = 0; batch < 1000; batch++) {
    processBatch(dataset.getBatch(batch)); // 1K function calls
}
```

**Performance Impact:**
- **Function call cost**: 5-20 CPU cycles per call
- **Row-based**: 5-20M cycles for function calls alone
- **Vectorized**: 5-20K cycles for function calls
- **Speedup**: 100-1000x reduction in overhead

### 4. Branch Prediction Optimization

```java
// Row-based: Unpredictable branches
for (Row row : dataset) {
    if (row.getSalary() > 50000) { // Unpredictable per row
        processHighSalary(row);
    } else {
        processLowSalary(row);
    }
}

// Vectorized: Predictable batch processing
for (Batch batch : dataset) {
    HighSalaryBatch highSalaries = batch.filter(salary > 50000);
    LowSalaryBatch lowSalaries = batch.filter(salary <= 50000);
    
    if (!highSalaries.isEmpty()) {
        processHighSalaryBatch(highSalaries); // Predictable branch
    }
    if (!lowSalaries.isEmpty()) {
        processLowSalaryBatch(lowSalaries);   // Predictable branch
    }
}
```

**Performance Impact:**
- **Branch misprediction penalty**: 10-20 CPU cycles
- **Row-based**: 20-40% misprediction rate
- **Vectorized**: 5-10% misprediction rate
- **Speedup**: 1.5-2x improvement

## Real-World Performance Examples

### Parquet File Reading

```java
// Row-based Parquet reading
ParquetReader<GenericRecord> reader = AvroParquetReader.builder(file).build();
GenericRecord record;
long startTime = System.currentTimeMillis();

while ((record = reader.read()) != null) {
    processRecord(record); // Process one record at a time
}

long rowBasedTime = System.currentTimeMillis() - startTime;
// Result: 120 seconds for 100M records

// Vectorized Parquet reading  
VectorizedParquetRecordReader vectorReader = new VectorizedParquetRecordReader();
ColumnarBatch batch;
startTime = System.currentTimeMillis();

while ((batch = vectorReader.nextBatch()) != null) {
    processBatch(batch); // Process 4096 records simultaneously
}

long vectorizedTime = System.currentTimeMillis() - startTime;
// Result: 12 seconds for 100M records
// Speedup: 10x faster
```

### Aggregation Operations

```java
// Performance comparison for SUM operation
Dataset: 100M double values

// Row-based aggregation
double sum = 0.0;
for (int i = 0; i < 100_000_000; i++) {
    sum += values[i];
}
// Time: 800ms

// Vectorized aggregation (using SIMD)
double sum = vectorizedSum(values); // Processes 8 doubles per instruction
// Time: 80ms
// Speedup: 10x faster
```

### Filter Operations

```java
// Performance comparison for filtering
Dataset: 100M records with salary column

// Row-based filtering
List<Record> result = new ArrayList<>();
for (Record record : dataset) {
    if (record.getSalary() > 50000) {
        result.add(record);
    }
}
// Time: 15 seconds

// Vectorized filtering
List<Record> result = dataset.vectorizedFilter(
    Expressions.greaterThan("salary", 50000)
);
// Time: 1.5 seconds  
// Speedup: 10x faster
```

## How Apache Iceberg Leverages Vectorization

### 1. Spark Integration with Vectorized Readers

```java
// VectorizedSparkParquetReaders.java
public class VectorizedReader implements PartitionReader<InternalRow> {
    private final VectorizedParquetRecordReader reader;
    private ColumnarBatch currentBatch;
    private int currentRow = 0;
    
    @Override
    public InternalRow next() {
        if (currentBatch == null || currentRow >= currentBatch.numRows()) {
            currentBatch = reader.nextBatch(); // Read 4096 rows at once
            currentRow = 0;
        }
        return currentBatch.getRow(currentRow++);
    }
    
    @Override
    public boolean next() {
        // Vectorized batch reading with automatic batching
        return reader.nextKeyValue();
    }
}
```

### 2. Column Pruning + Vectorization

```java
// Only read needed columns in vectorized batches
Table table = catalog.loadTable(TableIdentifier.of("sales", "transactions"));

TableScan scan = table.newScan()
    .select("customer_id", "amount", "transaction_date")  // Column pruning
    .filter(Expressions.greaterThan("amount", 1000));     // Predicate pushdown

// Results in:
// 1. Only 3 columns read instead of all 20+ columns
// 2. Vectorized reading of selected columns
// 3. Filter applied during vectorized reading
// Combined speedup: 15-30x faster than full table scan
```

### 3. Predicate Pushdown with Vectorized Execution

```java
// Filter applied during vectorized reading, not after
VectorizedParquetRecordReader reader = new VectorizedParquetRecordReader();

// Pushdown filter to Parquet reader
reader.setFilterPredicate(
    FilterApi.and(
        FilterApi.gt(doubleColumn("amount"), 1000.0),
        FilterApi.eq(binaryColumn("status"), Binary.fromString("ACTIVE"))
    )
);

// Benefits:
// 1. Entire batches skipped if no rows match
// 2. Vectorized filter evaluation within batches
// 3. Reduced I/O for filtered data
```

### 4. Manifest-Level Optimizations

```java
// Iceberg's manifest-based file pruning + vectorization
TableScan scan = table.newScan()
    .filter(Expressions.and(
        Expressions.greaterThan("transaction_date", "2023-01-01"),
        Expressions.equal("region", "US")
    ));

// Execution flow:
// 1. Manifest filtering eliminates 80% of files (metadata-only)
// 2. Remaining files read with vectorized execution
// 3. Column-level statistics skip entire row groups
// 4. Vectorized processing of qualifying data
// Combined effect: 50-100x speedup over full scan
```

## CPU Utilization Comparison

### Resource Utilization Metrics

```
Row-based Processing:
├── CPU Utilization: 30-40%
├── Memory Bandwidth: 20-30%
├── Cache Hit Rate: 60-70%
├── Branch Prediction: 70-80% accuracy
└── SIMD Usage: 0%

Vectorized Processing:
├── CPU Utilization: 80-90%
├── Memory Bandwidth: 70-80%
├── Cache Hit Rate: 85-95%
├── Branch Prediction: 90-95% accuracy
└── SIMD Usage: 60-80%
```

### Performance Scaling

```java
// Performance scaling with data size
public class PerformanceComparison {
    
    public void compareScaling() {
        int[] dataSizes = {1_000, 10_000, 100_000, 1_000_000, 10_000_000};
        
        for (int size : dataSizes) {
            long rowBasedTime = measureRowBased(size);
            long vectorizedTime = measureVectorized(size);
            
            double speedup = (double) rowBasedTime / vectorizedTime;
            System.out.printf("Size: %d, Speedup: %.1fx%n", size, speedup);
        }
    }
}

// Typical results:
// Size: 1,000, Speedup: 2.1x
// Size: 10,000, Speedup: 4.5x  
// Size: 100,000, Speedup: 8.2x
// Size: 1,000,000, Speedup: 12.1x
// Size: 10,000,000, Speedup: 15.3x
```

## Implementation Best Practices

### 1. Optimal Batch Sizes

```java
// Batch size tuning for different operations
public class BatchSizeOptimization {
    
    // Memory-bound operations (large data types)
    private static final int MEMORY_BOUND_BATCH_SIZE = 1024;
    
    // CPU-bound operations (simple computations)  
    private static final int CPU_BOUND_BATCH_SIZE = 4096;
    
    // I/O-bound operations (file reading)
    private static final int IO_BOUND_BATCH_SIZE = 8192;
    
    public int getOptimalBatchSize(OperationType type) {
        switch (type) {
            case MEMORY_BOUND: return MEMORY_BOUND_BATCH_SIZE;
            case CPU_BOUND: return CPU_BOUND_BATCH_SIZE;
            case IO_BOUND: return IO_BOUND_BATCH_SIZE;
            default: return 4096; // Default batch size
        }
    }
}
```

### 2. Memory Management

```java
// Efficient memory management for vectorized operations
public class VectorizedProcessor {
    
    private final MemoryPool memoryPool;
    private final int batchSize;
    
    public void processData(Dataset dataset) {
        // Pre-allocate vectors to avoid GC pressure
        IntVector ids = memoryPool.allocateIntVector(batchSize);
        DoubleVector amounts = memoryPool.allocateDoubleVector(batchSize);
        
        try {
            for (Batch batch : dataset.getBatches(batchSize)) {
                // Reuse pre-allocated vectors
                batch.copyTo(ids, amounts);
                
                // Vectorized processing
                processVectorized(ids, amounts);
            }
        } finally {
            // Clean up allocated memory
            memoryPool.release(ids);
            memoryPool.release(amounts);
        }
    }
}
```

### 3. Error Handling in Vectorized Operations

```java
// Robust error handling for batch operations
public class VectorizedErrorHandling {
    
    public ProcessingResult processBatch(ColumnarBatch batch) {
        ProcessingResult result = new ProcessingResult();
        
        try {
            // Attempt vectorized processing
            VectorizedResult vectorResult = processVectorized(batch);
            result.addSuccessful(vectorResult);
            
        } catch (VectorizationException e) {
            // Fallback to row-based processing for problematic batch
            logger.warn("Vectorization failed, falling back to row-based: {}", e.getMessage());
            
            for (int i = 0; i < batch.numRows(); i++) {
                try {
                    RowResult rowResult = processRow(batch.getRow(i));
                    result.addSuccessful(rowResult);
                } catch (Exception rowException) {
                    result.addFailed(i, rowException);
                }
            }
        }
        
        return result;
    }
}
```

## Key Performance Benefits Summary

### 1. Throughput Improvements
- **Analytical queries**: 10-20x faster
- **Aggregations**: 5-15x faster  
- **Filtering**: 8-12x faster
- **File I/O**: 3-8x faster

### 2. Resource Efficiency
- **CPU utilization**: 2-3x better
- **Memory bandwidth**: 2-4x better
- **Cache efficiency**: 3-5x better
- **Energy consumption**: 40-60% reduction

### 3. Scalability Benefits
- **Linear scaling**: Performance scales with data size
- **Parallel processing**: Better utilization of multi-core CPUs
- **Memory efficiency**: Lower memory overhead per operation
- **Network efficiency**: Reduced data movement

## The Mathematics Behind 10x Speedup

The "10x faster" claim comes from combining multiple optimizations:

```
Total Speedup = SIMD_Speedup × Cache_Speedup × Overhead_Speedup × Branch_Speedup

Typical values:
├── SIMD Instructions: 2-4x speedup
├── Better Cache Locality: 2-3x speedup  
├── Reduced Overhead: 1.5-2x speedup
└── Branch Prediction: 1.2-1.5x speedup

Combined Effect: 2×2×1.5×1.2 = 7.2x to 4×3×2×1.5 = 36x
Practical Range: 6-24x speedup
Typical Result: ~10x speedup
```

## Conclusion

Vectorized execution represents a **fundamental shift** in how modern analytical systems process data. By leveraging:

- **SIMD instructions** for parallel computation
- **Columnar memory layout** for cache efficiency  
- **Batch processing** to reduce overhead
- **Predictable access patterns** for CPU optimization

Systems like Apache Iceberg with Spark, Flink, and Trino can achieve **10x or greater performance improvements** over traditional row-based processing.

This performance advantage is **critical for modern data lakes** where:
- **Data volumes** are measured in petabytes
- **Query latency** requirements are increasingly strict
- **Cost efficiency** drives architectural decisions
- **Real-time analytics** demand high throughput

Vectorized execution is not just an optimization—it's a **necessity** for competitive performance in modern analytical workloads.
