# Apache Iceberg Optimistic Concurrency Control

## Overview

Apache Iceberg implements optimistic concurrency control to allow multiple writers to work on the same table simultaneously without blocking each other. This approach maximizes throughput while ensuring data consistency through conflict detection and retry mechanisms.

## How Iceberg Implements Optimistic Concurrency

### 1. Metadata Versioning

Iceberg uses **metadata files** with sequential version numbers to track table state:

```
table/
├── metadata/
│   ├── v1.metadata.json  # Version 1
│   ├── v2.metadata.json  # Version 2
│   └── v3.metadata.json  # Version 3
└── version-hint.text     # Points to latest version
```

Each metadata file contains:
- Schema definition
- Partition specification  
- Snapshot history
- Current snapshot pointer

### 2. Transaction Flow

#### Step 1: Read Current Metadata
```java
// BaseTable.java - Load current metadata
TableMetadata current = ops.current();
long currentVersion = current.formatVersion();
```

Writers start by reading the current table metadata to understand the table's state.

#### Step 2: Build Transaction Locally
```java
// BaseTransaction.java - Create transaction
Transaction txn = table.newTransaction();
txn.newAppend()
   .appendFile(dataFile)
   .commit();
```

All changes are accumulated locally without immediately writing to storage.

#### Step 3: Atomic Commit Attempt
```java
// BaseTableOperations.java - Atomic commit
public TableMetadata commit(TableMetadata base, TableMetadata metadata) {
    String newMetadataLocation = writeNewMetadata(metadata);
    
    // Atomic operation - fails if version changed
    if (!atomicCommit(base, newMetadataLocation)) {
        throw new CommitFailedException("Concurrent modification detected");
    }
    
    return metadata;
}
```

The commit operation is atomic - it either succeeds completely or fails if another writer committed first.

### 3. Conflict Detection Mechanisms

#### Version-Based Detection
```java
// Check if base metadata is still current
if (!current.metadataFileLocation().equals(base.metadataFileLocation())) {
    // Another writer committed - conflict detected
    throw new CommitFailedException("Table metadata changed");
}
```

#### Catalog-Level Atomic Operations
Different catalog implementations provide atomic commit guarantees:

**Hive Metastore:**
```java
// HiveCatalog.java - Uses Hive's atomic table property updates
table.getParameters().put("metadata_location", newLocation);
metastore.alter_table(table); // Atomic operation
```

**Hadoop Catalog:**
```java
// HadoopCatalog.java - Uses filesystem atomic rename
Path tempFile = new Path(metadataDir, "temp-" + UUID.randomUUID());
Path finalFile = new Path(metadataDir, "v" + newVersion + ".metadata.json");

// Write to temp location first
writeMetadata(tempFile, metadata);

// Atomic rename operation
if (!fs.rename(tempFile, finalFile)) {
    throw new CommitFailedException("Failed to commit metadata");
}
```

### 4. Retry Logic

When conflicts are detected, Iceberg automatically retries the operation:

```java
// BaseTransaction.java - Retry mechanism
public void commitTransaction() {
    int attempts = 0;
    while (attempts < maxRetries) {
        try {
            TableMetadata current = ops.current();
            TableMetadata updated = apply(current, changes);
            ops.commit(current, updated);
            return; // Success
        } catch (CommitFailedException e) {
            attempts++;
            if (attempts >= maxRetries) {
                throw e;
            }
            // Exponential backoff before retry
            Thread.sleep(backoffMs * (1 << attempts));
        }
    }
}
```

### 5. Snapshot Isolation

Iceberg provides snapshot isolation through immutable snapshots:

```java
// Each snapshot is immutable and has a unique ID
public class Snapshot {
    private final long snapshotId;
    private final Long parentId;
    private final long timestampMillis;
    private final List<ManifestFile> manifests;
    
    // Snapshots never change once created
}
```

Readers can access any historical snapshot without being affected by concurrent writes.

## Benefits of Iceberg's Approach

### 1. **High Concurrency**
- Multiple writers can work simultaneously
- No blocking locks during data writing
- Only brief contention during metadata commits

### 2. **Consistency Guarantees**
- ACID transactions at the table level
- Readers see consistent snapshots
- No partial or corrupted data visible

### 3. **Automatic Conflict Resolution**
- Built-in retry mechanisms
- Exponential backoff prevents thundering herd
- Transparent to application code

### 4. **Scalability**
- Performance scales with number of writers
- Minimal coordination overhead
- Works across distributed systems

## Example Scenario

Consider two writers updating the same table:

```
Writer A                    Writer B
--------                    --------
1. Read metadata v5         1. Read metadata v5
2. Add files locally        2. Add files locally  
3. Commit → creates v6      3. Commit → FAILS (v5 outdated)
                           4. Retry: Read v6
                           5. Merge changes with v6
                           6. Commit → creates v7
```

Writer B's commit fails because the base version (v5) is no longer current. The retry mechanism automatically handles this by:
1. Reading the new current metadata (v6)
2. Applying Writer B's changes on top of v6
3. Successfully committing as v7

## Key Implementation Files

- **[BaseTable.java](sources/iceberg/core/src/main/java/org/apache/iceberg/BaseTable.java)** - Main table interface
- **[BaseTransaction.java](sources/iceberg/core/src/main/java/org/apache/iceberg/BaseTransaction.java)** - Transaction implementation
- **[BaseTableOperations.java](sources/iceberg/core/src/main/java/org/apache/iceberg/BaseTableOperations.java)** - Metadata operations
- **[HiveCatalog.java](sources/iceberg/hive-metastore/src/main/java/org/apache/iceberg/hive/HiveCatalog.java)** - Hive-based atomic commits
- **[HadoopCatalog.java](sources/iceberg/core/src/main/java/org/apache/iceberg/hadoop/HadoopCatalog.java)** - Filesystem-based atomic commits

This optimistic concurrency model makes Iceberg highly suitable for modern data lake architectures where multiple processing engines need to write to the same tables concurrently.
