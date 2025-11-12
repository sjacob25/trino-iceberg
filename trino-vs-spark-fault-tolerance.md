# Trino vs Spark Fault Tolerance: Architecture and Trade-offs

## Executive Summary

| Aspect | Trino | Spark |
|--------|-------|-------|
| **Philosophy** | Fail Fast | Fault Tolerant |
| **Query Failure** | Entire query fails | Task-level retry |
| **Recovery** | Manual restart | Automatic retry |
| **Use Case** | Interactive analytics | Batch processing |
| **Latency** | Low (seconds) | Higher (minutes) |
| **Resilience** | Low | High |

## Trino Fault Tolerance

### Core Philosophy: Fail Fast

Trino is designed for **interactive, low-latency queries** where speed is more important than fault tolerance.

```
User Query → Fast Result (seconds)
     ↓
If ANY failure → Fail immediately → User retries
```

### Architecture

**Query Execution Model:**
```
┌─────────────────┐
│   Coordinator   │ ← Single point of coordination
└─────────┬───────┘
          │
    ┌─────┼─────┐
    ▼     ▼     ▼
┌─────┐ ┌─────┐ ┌─────┐
│ W1  │ │ W2  │ │ W3  │ ← Workers execute tasks
└─────┘ └─────┘ └─────┘

If W2 fails → Entire query fails
```

### Failure Scenarios

**1. Worker Node Failure**
```java
// Trino behavior
try {
    executeQuery("SELECT * FROM large_table WHERE condition");
} catch (TrinoException e) {
    // Worker failed - entire query fails
    // Error: "Query failed: Worker node worker-2 is no longer available"
    
    // Solution: Retry entire query
    executeQuery("SELECT * FROM large_table WHERE condition");
}
```

**2. Network Partition**
```
Coordinator ──X──→ Worker 2 (network issue)
            ├────→ Worker 1 ✅
            └────→ Worker 3 ✅

Result: Query fails immediately
Error: "Remote task execution failed"
```

**3. Out of Memory**
```sql
-- Large aggregation query
SELECT customer_id, COUNT(*), SUM(amount) 
FROM orders 
GROUP BY customer_id;

-- If any worker runs out of memory:
-- Error: "Query exceeded per-node memory limit"
-- Entire query fails
```

### Trino's Fault Tolerance Features

**Limited Retry Mechanisms:**
```properties
# coordinator config
query.max-execution-time=1h
query.max-run-time=2h

# Some retries for transient issues
query.remote-task.max-error-duration=5m
```

**Graceful Degradation:**
```java
// Trino can handle some worker failures during startup
// But once query starts, any failure kills the query
public class QueryExecution {
    public void execute() {
        if (workerFails()) {
            throw new QueryFailedException("Worker failed");
            // No automatic retry
        }
    }
}
```

### When Trino Fails

**Common Failure Scenarios:**
- **Hardware failure** (disk, memory, network)
- **Resource exhaustion** (OOM, disk space)
- **Network partitions**
- **Software bugs** (JVM crashes)
- **Configuration issues**

**Impact:**
- **Entire query fails**
- **All intermediate results lost**
- **User must retry manually**
- **No partial results available**

## Spark Fault Tolerance

### Core Philosophy: Resilient Distributed Datasets (RDDs)

Spark is designed for **fault-tolerant batch processing** where job completion is more important than latency.

```
User Job → Resilient Execution (minutes/hours)
    ↓
If failure → Automatic retry → Job continues
```

### Architecture

**RDD Lineage Model:**
```
┌─────────────────┐
│     Driver      │ ← Tracks RDD lineage
└─────────┬───────┘
          │
    ┌─────┼─────┐
    ▼     ▼     ▼
┌─────┐ ┌─────┐ ┌─────┐
│ E1  │ │ E2  │ │ E3  │ ← Executors process partitions
└─────┘ └─────┘ └─────┘

If E2 fails → Recompute lost partitions using lineage
```

### RDD Lineage Example

```scala
// Spark RDD transformations create lineage graph
val data = spark.read.parquet("hdfs://data/")           // RDD1
val filtered = data.filter($"amount" > 1000)            // RDD2 = filter(RDD1)
val grouped = filtered.groupBy($"customer_id")          // RDD3 = groupBy(RDD2)
val result = grouped.agg(sum($"amount"))                 // RDD4 = agg(RDD3)

// Lineage: RDD4 → RDD3 → RDD2 → RDD1 → HDFS
// If RDD3 partition fails, Spark recomputes: RDD1 → RDD2 → RDD3
```

### Fault Tolerance Mechanisms

**1. Task-Level Retry**
```scala
// Spark configuration
spark.task.maxAttempts = 3
spark.task.maxFailures = 1

// Automatic retry behavior
def executeTask(partition: Partition): Iterator[Row] = {
  try {
    processPartition(partition)
  } catch {
    case e: Exception =>
      // Spark automatically retries up to maxAttempts
      logWarning(s"Task failed, retrying: ${e.getMessage}")
      throw e  // Spark handles retry
  }
}
```

**2. Stage-Level Recovery**
```scala
// If task retries exceed limit, recompute entire stage
class DAGScheduler {
  def handleTaskFailure(task: Task, reason: TaskFailureReason): Unit = {
    if (task.attemptNumber >= maxTaskAttempts) {
      // Recompute parent stages
      resubmitFailedStages(task.stageId)
    }
  }
}
```

**3. RDD Checkpointing**
```scala
// Persist intermediate results to avoid recomputation
val expensiveRDD = data.map(expensiveTransformation)
expensiveRDD.checkpoint()  // Save to HDFS/S3

val result = expensiveRDD.filter(condition).collect()
// If failure occurs after checkpoint, no need to recompute expensiveRDD
```

**4. Dynamic Allocation**
```scala
// Spark can request new executors to replace failed ones
spark.dynamicAllocation.enabled = true
spark.dynamicAllocation.maxExecutors = 100

// If executor fails, Spark requests replacement
class ExecutorAllocationManager {
  def onExecutorRemoved(executorId: String): Unit = {
    requestNewExecutor()  // Replace failed executor
  }
}
```

### Failure Recovery Examples

**Executor Failure:**
```
Job: Process 1TB of data across 100 partitions

Executor-2 fails while processing partitions 20-29
↓
Spark Action:
1. Mark partitions 20-29 as failed
2. Request new executor (Executor-5)
3. Recompute partitions 20-29 on Executor-5
4. Continue job execution
5. Job completes successfully
```

**Driver Failure (with checkpointing):**
```scala
// Spark Streaming with checkpointing
val ssc = new StreamingContext(conf, Seconds(10))
ssc.checkpoint("hdfs://checkpoints/")

// If driver fails:
// 1. Restart driver
// 2. Recover from checkpoint
// 3. Resume processing from last checkpoint
val recoveredSSC = StreamingContext.getOrCreate("hdfs://checkpoints/", createContext)
```

## Performance Comparison

### Query Latency

**Trino (No Failures):**
```sql
-- Simple aggregation on 1TB data
SELECT region, SUM(sales) FROM orders GROUP BY region;
-- Execution time: 30 seconds
```

**Spark (No Failures):**
```scala
// Same query in Spark
df.groupBy("region").agg(sum("sales"))
// Execution time: 2 minutes (higher overhead)
```

**With Failures:**

**Trino:**
```
Attempt 1: 25 seconds → Worker fails → Query fails
Attempt 2: 30 seconds → Success
Total time: 55 seconds (manual retry)
```

**Spark:**
```
Single job: 2 minutes → Executor fails → Auto retry → Success
Total time: 3 minutes (automatic recovery)
```

### Resource Utilization

**Trino:**
```
Memory: Lower overhead (no lineage tracking)
CPU: Optimized for speed
Network: Efficient data shuffling
Storage: No intermediate checkpoints
```

**Spark:**
```
Memory: Higher overhead (RDD lineage, caching)
CPU: Additional overhead for fault tolerance
Network: More data movement for recovery
Storage: Checkpointing overhead
```

## Use Case Recommendations

### Choose Trino When:

**Interactive Analytics:**
```sql
-- Dashboard queries (seconds response time)
SELECT * FROM sales WHERE date = current_date;

-- Ad-hoc exploration
SELECT customer_type, AVG(order_value) 
FROM orders 
WHERE region = 'US' 
GROUP BY customer_type;
```

**Characteristics:**
- **Query duration**: Seconds to minutes
- **Failure tolerance**: Low (acceptable to retry)
- **Latency requirements**: Low
- **Data size**: Small to medium (GBs to TBs)

### Choose Spark When:

**Batch Processing:**
```scala
// ETL pipelines (hours of processing)
val dailyReport = rawData
  .filter(isValidRecord)
  .join(customerData)
  .groupBy("date", "region")
  .agg(sum("revenue"), count("orders"))
  .write.parquet("hdfs://reports/daily/")
```

**Characteristics:**
- **Job duration**: Minutes to hours
- **Failure tolerance**: High (must complete)
- **Latency requirements**: Higher acceptable
- **Data size**: Large (TBs to PBs)

## Hybrid Approaches

### Lambda Architecture
```
┌─────────────────┐    ┌─────────────────┐
│  Batch Layer    │    │  Speed Layer    │
│    (Spark)      │    │    (Trino)      │
│                 │    │                 │
│ • Fault tolerant│    │ • Low latency   │
│ • High throughput│   │ • Interactive   │
│ • Historical data│   │ • Recent data   │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────┬───────────────┘
                 ▼
        ┌─────────────────┐
        │  Serving Layer  │
        │   (Combined)    │
        └─────────────────┘
```

### Complementary Usage
```sql
-- Use Spark for ETL (fault tolerant)
spark.sql("""
  INSERT INTO warehouse.daily_sales
  SELECT date, region, SUM(amount)
  FROM raw.transactions
  WHERE date = current_date
  GROUP BY date, region
""")

-- Use Trino for analytics (fast)
trino.execute("""
  SELECT region, sales_trend
  FROM warehouse.daily_sales
  WHERE date >= current_date - interval '30' day
""")
```

## Configuration Best Practices

### Trino Optimization for Reliability

```properties
# coordinator config
query.max-execution-time=30m
query.max-run-time=1h
query.max-memory-per-node=8GB

# worker config
task.max-worker-threads=200
task.min-drivers=4

# Retry configuration
query.remote-task.max-error-duration=2m
exchange.client-threads=25
```

### Spark Optimization for Fault Tolerance

```scala
// Spark configuration
val conf = new SparkConf()
  .set("spark.task.maxAttempts", "3")
  .set("spark.stage.maxConsecutiveAttempts", "8")
  .set("spark.kubernetes.executor.deleteOnTermination", "false")
  .set("spark.sql.adaptive.enabled", "true")
  .set("spark.sql.adaptive.coalescePartitions.enabled", "true")
  .set("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
  .set("spark.dynamicAllocation.enabled", "true")
  .set("spark.dynamicAllocation.maxExecutors", "100")
```

## Monitoring and Alerting

### Trino Monitoring

```sql
-- Query failure monitoring
SELECT 
  query_id,
  query_state,
  error_message,
  execution_time
FROM system.runtime.queries 
WHERE query_state = 'FAILED'
  AND created > current_timestamp - interval '1' hour;
```

### Spark Monitoring

```scala
// Spark application monitoring
spark.sparkContext.statusTracker.getExecutorInfos.foreach { executor =>
  if (executor.isActive == false) {
    logger.warn(s"Executor ${executor.executorId} failed")
  }
}

// Task failure monitoring
spark.sparkContext.addSparkListener(new SparkListener {
  override def onTaskEnd(taskEnd: SparkListenerTaskEnd): Unit = {
    if (taskEnd.reason.isInstanceOf[TaskFailedReason]) {
      logger.error(s"Task failed: ${taskEnd.reason}")
    }
  }
})
```

## Conclusion

### Key Takeaways

**Trino:**
- **Fast execution** with minimal overhead
- **Fail-fast approach** for quick feedback
- **Best for interactive workloads** where retry is acceptable
- **Lower resource overhead** but less resilient

**Spark:**
- **Fault-tolerant execution** with automatic recovery
- **Higher latency** due to fault tolerance overhead
- **Best for batch processing** where completion is critical
- **Higher resource overhead** but more resilient

### Decision Framework

```
Query Duration < 5 minutes + Interactive Use Case → Trino
Query Duration > 30 minutes + Batch Processing → Spark
Mixed Workload → Use both (Lambda Architecture)
```

The choice between Trino and Spark fault tolerance models depends on your specific requirements for latency, reliability, and resource utilization.
