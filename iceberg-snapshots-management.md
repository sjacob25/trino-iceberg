# Apache Iceberg Snapshots: Creation, Usage, and Management

## What is a Snapshot?

A **snapshot** in Apache Iceberg represents the **complete state of a table at a specific point in time**. It's an immutable reference that captures:

- **All data files** that comprise the table
- **Schema version** at that point
- **Partition specification** used
- **Metadata** about the operation that created it
- **Timestamp** of creation
- **Parent snapshot** reference (forming a lineage)

```json
{
  "snapshot-id": 3051729675574597004,
  "parent-snapshot-id": 3051729675574597003,
  "timestamp-ms": 1515100955770,
  "summary": {
    "operation": "append",
    "added-data-files": "4",
    "added-records": "4444",
    "added-files-size": "31616"
  },
  "manifest-list": "s3://bucket/table/metadata/snap-3051729675574597004-1-7e6760f0-4f6c-4b23-b907-0a5a174e3863.avro"
}
```

## Snapshot Architecture

### Hierarchical Structure

```
Table Metadata
├── Current Snapshot ID: 12345
├── Snapshot History
│   ├── Snapshot 12345 (current)
│   │   ├── Manifest List
│   │   │   ├── manifest-001.avro
│   │   │   ├── manifest-002.avro
│   │   │   └── manifest-003.avro
│   │   └── Summary: {operation: "append", added-files: 5}
│   ├── Snapshot 12344 (parent)
│   │   ├── Manifest List
│   │   └── Summary: {operation: "overwrite", deleted-files: 2}
│   └── Snapshot 12343 (grandparent)
└── Snapshot References
    ├── main → 12345
    └── audit-branch → 12344
```

### Immutability Principle

```java
// Snapshots are immutable - once created, never modified
public class BaseSnapshot implements Snapshot {
    private final long snapshotId;
    private final Long parentId;
    private final long timestampMillis;
    private final List<ManifestFile> allManifests; // Immutable list
    
    // No setters - all data set at construction time
    public BaseSnapshot(long snapshotId, Long parentId, long timestampMillis, 
                       String operation, Map<String, String> summary, 
                       String manifestListLocation) {
        this.snapshotId = snapshotId;
        this.parentId = parentId;
        this.timestampMillis = timestampMillis;
        // ... initialize immutable state
    }
}
```

## Snapshot Creation Process

### 1. Append Operation

```java
// AppendFiles operation creates new snapshot
Table table = catalog.loadTable(TableIdentifier.of("db", "sales"));

AppendFiles append = table.newAppend();
append.appendFile(dataFile1);
append.appendFile(dataFile2);
append.commit(); // Creates new snapshot

// Internal process:
// 1. Generate new snapshot ID
// 2. Create manifest entries for new files
// 3. Write new manifest files
// 4. Create manifest list
// 5. Update table metadata with new snapshot
```

**Creation Steps:**
1. **Generate Snapshot ID**: Unique identifier (typically timestamp-based)
2. **Collect Changes**: Gather all files being added/removed
3. **Write Manifests**: Create manifest files for new data
4. **Create Manifest List**: Aggregate all manifests for this snapshot
5. **Update Metadata**: Atomically update table metadata

### 2. Overwrite Operation

```java
// Overwrite creates snapshot that replaces data
OverwriteFiles overwrite = table.newOverwrite();
overwrite.addFile(newDataFile);
overwrite.deleteFile(oldDataFile);
overwrite.commit(); // New snapshot with replaced data

// Results in:
// - New snapshot with different manifest list
// - Old files marked as deleted in manifests
// - New files added to manifests
```

### 3. Delete Operation

```java
// Delete operation creates snapshot with fewer files
DeleteFiles delete = table.newDelete();
delete.deleteFromRowFilter(Expressions.equal("status", "inactive"));
delete.commit(); // Snapshot with delete files or removed data files
```

## Snapshot Usage Scenarios

### 1. Time Travel Queries

```sql
-- Query table as it existed at specific timestamp
SELECT * FROM sales TIMESTAMP AS OF '2023-12-01 10:00:00';

-- Query specific snapshot by ID
SELECT * FROM sales VERSION AS OF 3051729675574597004;
```

**Implementation:**
```java
// Time travel scan
TableScan scan = table.newScan()
    .useSnapshot(snapshotId);

CloseableIterable<Record> records = IcebergGenerics
    .read(table)
    .useSnapshot(snapshotId)
    .build();
```

### 2. Incremental Processing

```java
// Process only changes between snapshots
IncrementalAppendScan incrementalScan = table.newIncrementalAppendScan()
    .fromSnapshotExclusive(lastProcessedSnapshot)
    .toSnapshot(currentSnapshot);

// Returns only files added between snapshots
for (FileScanTask task : incrementalScan.planFiles()) {
    processNewData(task);
}
```

### 3. Rollback Operations

```java
// Rollback to previous snapshot
table.manageSnapshots()
    .setCurrentSnapshot(previousSnapshotId)
    .commit();

// Or rollback to specific timestamp
table.manageSnapshots()
    .rollbackToTime(System.currentTimeMillis() - TimeUnit.HOURS.toMillis(2))
    .commit();
```

### 4. Branching and Tagging

```java
// Create branch from current snapshot
table.manageSnapshots()
    .createBranch("experiment-branch", currentSnapshotId)
    .commit();

// Create tag for important milestone
table.manageSnapshots()
    .createTag("v1.0-release", snapshotId)
    .commit();

// Switch to branch
table.manageSnapshots()
    .setCurrentSnapshot("experiment-branch")
    .commit();
```

## Snapshot Management Principles

### 1. Retention Policies

#### Time-Based Retention
```java
// Expire snapshots older than 7 days
table.expireSnapshots()
    .expireOlderThan(System.currentTimeMillis() - TimeUnit.DAYS.toMillis(7))
    .commit();
```

#### Count-Based Retention
```java
// Keep only last 100 snapshots
table.expireSnapshots()
    .retainLast(100)
    .commit();
```

#### Custom Retention Logic
```java
// Advanced retention with custom logic
ExpireSnapshots expire = table.expireSnapshots();

// Always retain tagged snapshots
for (SnapshotRef ref : table.refs().values()) {
    if (ref.isTag()) {
        expire.retainSnapshot(ref.snapshotId());
    }
}

// Retain daily snapshots for 30 days
long thirtyDaysAgo = System.currentTimeMillis() - TimeUnit.DAYS.toMillis(30);
for (Snapshot snapshot : table.snapshots()) {
    if (snapshot.timestampMillis() > thirtyDaysAgo && 
        isDailySnapshot(snapshot)) {
        expire.retainSnapshot(snapshot.snapshotId());
    }
}

expire.commit();
```

### 2. Snapshot Lineage Management

#### Linear History
```
Snapshot A → Snapshot B → Snapshot C → Snapshot D (current)
```

#### Branched History
```
                    ┌─ Snapshot E (experiment-branch)
                    │
Snapshot A → Snapshot B → Snapshot C → Snapshot D (main)
                    │
                    └─ Snapshot F (feature-branch)
```

#### Merge Operations
```java
// Merge branch back to main
table.manageSnapshots()
    .cherrypick(experimentBranchSnapshotId)
    .commit();

// Fast-forward merge
table.manageSnapshots()
    .fastForward("main", "feature-branch")
    .commit();
```

### 3. Performance Optimization

#### Manifest Consolidation
```java
// Consolidate small manifests for better performance
table.rewriteManifests()
    .rewriteIf(manifest -> manifest.length() < 10 * 1024 * 1024) // < 10MB
    .commit();
```

#### Snapshot Compaction
```java
// Compact snapshot history to reduce metadata size
table.expireSnapshots()
    .expireOlderThan(cutoffTime)
    .deleteWith(file -> {
        // Custom cleanup logic
        cleanupOrphanedFiles(file);
    })
    .commit();
```

## Administrative Operations

### 1. Snapshot Inspection

```java
// List all snapshots
for (Snapshot snapshot : table.snapshots()) {
    System.out.printf("Snapshot %d: %s at %s%n",
        snapshot.snapshotId(),
        snapshot.operation(),
        Instant.ofEpochMilli(snapshot.timestampMillis()));
}

// Get snapshot details
Snapshot snapshot = table.snapshot(snapshotId);
Map<String, String> summary = snapshot.summary();
System.out.println("Added files: " + summary.get("added-data-files"));
System.out.println("Total records: " + summary.get("total-records"));
```

### 2. Snapshot Validation

```java
// Validate snapshot integrity
public class SnapshotValidator {
    
    public ValidationResult validate(Snapshot snapshot) {
        ValidationResult result = new ValidationResult();
        
        // Check manifest list exists
        if (!fileExists(snapshot.manifestListLocation())) {
            result.addError("Manifest list not found: " + snapshot.manifestListLocation());
        }
        
        // Validate all manifests
        for (ManifestFile manifest : snapshot.allManifests()) {
            if (!fileExists(manifest.path())) {
                result.addError("Manifest not found: " + manifest.path());
            }
            
            // Validate manifest content
            validateManifestContent(manifest, result);
        }
        
        return result;
    }
}
```

### 3. Snapshot Recovery

```java
// Recover from corrupted snapshot
public class SnapshotRecovery {
    
    public void recoverFromCorruption(Table table, long corruptedSnapshotId) {
        // Find last known good snapshot
        Snapshot lastGood = findLastValidSnapshot(table, corruptedSnapshotId);
        
        // Rollback to last good snapshot
        table.manageSnapshots()
            .setCurrentSnapshot(lastGood.snapshotId())
            .commit();
        
        // Remove corrupted snapshots
        table.expireSnapshots()
            .expireSnapshot(corruptedSnapshotId)
            .commit();
    }
}
```

### 4. Monitoring and Metrics

```java
// Snapshot metrics collection
public class SnapshotMetrics {
    
    public SnapshotStats collectStats(Table table) {
        List<Snapshot> snapshots = Lists.newArrayList(table.snapshots());
        
        return SnapshotStats.builder()
            .totalSnapshots(snapshots.size())
            .oldestSnapshot(snapshots.get(0).timestampMillis())
            .newestSnapshot(snapshots.get(snapshots.size() - 1).timestampMillis())
            .averageSnapshotSize(calculateAverageSize(snapshots))
            .snapshotGrowthRate(calculateGrowthRate(snapshots))
            .build();
    }
}
```

## Best Practices for Snapshot Management

### 1. Retention Strategy

```yaml
# Example retention configuration
snapshot_retention:
  # Keep all snapshots for 24 hours
  minimum_age_hours: 24
  
  # Keep daily snapshots for 30 days
  daily_retention_days: 30
  
  # Keep weekly snapshots for 1 year
  weekly_retention_weeks: 52
  
  # Always retain tagged snapshots
  retain_tags: true
  
  # Maximum snapshots to keep
  max_snapshots: 1000
```

### 2. Automated Cleanup

```java
// Scheduled snapshot cleanup job
@Scheduled(cron = "0 2 * * * *") // Run at 2 AM daily
public void cleanupSnapshots() {
    for (Table table : getAllTables()) {
        try {
            table.expireSnapshots()
                .expireOlderThan(System.currentTimeMillis() - RETENTION_PERIOD)
                .retainLast(MIN_SNAPSHOTS_TO_KEEP)
                .commit();
                
            logger.info("Cleaned up snapshots for table: {}", table.name());
        } catch (Exception e) {
            logger.error("Failed to cleanup snapshots for table: {}", table.name(), e);
        }
    }
}
```

### 3. Snapshot Naming Convention

```java
// Consistent snapshot tagging
public class SnapshotTagger {
    
    public void tagSnapshot(Table table, long snapshotId, String operation) {
        String tagName = String.format("%s_%s_%d", 
            operation.toLowerCase(),
            LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE),
            snapshotId);
            
        table.manageSnapshots()
            .createTag(tagName, snapshotId)
            .commit();
    }
}
```

### 4. Performance Monitoring

```java
// Monitor snapshot performance impact
public class SnapshotPerformanceMonitor {
    
    public void monitorScanPerformance(TableScan scan) {
        long startTime = System.currentTimeMillis();
        
        CloseableIterable<FileScanTask> tasks = scan.planFiles();
        int fileCount = Iterables.size(tasks);
        
        long planningTime = System.currentTimeMillis() - startTime;
        
        // Alert if planning takes too long
        if (planningTime > PLANNING_THRESHOLD_MS) {
            alertSlowPlanning(scan.table().name(), fileCount, planningTime);
        }
    }
}
```

## Troubleshooting Common Issues

### 1. Snapshot Explosion

**Problem**: Too many snapshots causing metadata bloat

**Solution**:
```java
// Aggressive cleanup for snapshot explosion
table.expireSnapshots()
    .expireOlderThan(System.currentTimeMillis() - TimeUnit.HOURS.toMillis(6))
    .retainLast(10)
    .commit();

// Consolidate manifests
table.rewriteManifests()
    .rewriteIf(manifest -> true) // Rewrite all manifests
    .commit();
```

### 2. Orphaned Files

**Problem**: Data files not referenced by any snapshot

**Solution**:
```java
// Clean up orphaned files
Actions.forTable(table)
    .deleteOrphanFiles()
    .olderThan(System.currentTimeMillis() - TimeUnit.DAYS.toMillis(3))
    .execute();
```

### 3. Slow Query Planning

**Problem**: Query planning takes too long due to many manifests

**Solution**:
```java
// Optimize manifest structure
table.rewriteManifests()
    .rewriteIf(manifest -> manifest.hasAddedFiles() || manifest.hasDeletedFiles())
    .commit();

// Use partition-based manifest organization
table.updateProperties()
    .set(TableProperties.MANIFEST_TARGET_SIZE_BYTES, "134217728") // 128MB
    .commit();
```

## Conclusion

Apache Iceberg's snapshot system provides:

- **Time Travel**: Query historical data states
- **ACID Guarantees**: Atomic, consistent operations
- **Branching**: Parallel development workflows
- **Rollback**: Easy recovery from issues
- **Incremental Processing**: Efficient change detection

Proper snapshot management is crucial for:
- **Performance**: Avoiding metadata bloat
- **Storage Costs**: Cleaning up unused data
- **Operational Efficiency**: Automated maintenance
- **Data Governance**: Audit trails and compliance

The immutable, versioned nature of snapshots makes Iceberg ideal for modern data lake architectures requiring both performance and reliability.
