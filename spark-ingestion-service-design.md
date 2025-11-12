# Spark Ingestion Service: Design Document

## Executive Summary

This document outlines the design for a managed Spark-based data ingestion service that provides multi-tenant ETL capabilities with flexible resource allocation models. The service supports both dedicated and shared resource allocation patterns with intelligent capacity management and SLA-based job promotion.

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Spark Ingestion Service                     │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Tenant    │  │  Resource   │  │    Job Scheduler &      │  │
│  │ Management  │  │ Management  │  │   Capacity Manager      │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ Estimation  │  │   SLA &     │  │      Monitoring &       │  │
│  │   Engine    │  │ Promotion   │  │      Analytics          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    Kubernetes Namespaces                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ dedicated-  │  │ vcpu-hours- │  │    draft-ingestion-     │  │
│  │   cpu-ns    │  │     ns      │  │          ns             │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Resource Allocation Models

### 1. Dedicated Ingestion Units

**Model:** 1:1 mapping to underlying Spark units
- **Purchase:** Fixed number of units (e.g., 100 units)
- **Allocation:** Reserved CPU/Memory exclusively for tenant
- **Namespace:** `dedicated-cpu-ns`

**Pros:**
- Predictable performance
- No resource contention
- Guaranteed availability
- Simple billing model

**Cons:**
- Higher cost due to reserved resources
- Potential resource waste during idle periods
- Less flexibility for varying workloads

### 2. vCPU Hours Model

**Model:** Time-based resource consumption
- **Purchase:** vCPU hours for specific time periods
- **Allocation:** Shared pool with consumption tracking
- **Namespace:** `vcpu-hours-ns`

#### Time Period Options Analysis

| Period | Pros | Cons | Use Case |
|--------|------|------|----------|
| **Hourly** | • Granular control<br>• Pay-as-you-go<br>• Good for testing | • Complex billing<br>• Frequent purchases<br>• Higher admin overhead | Development/Testing |
| **Daily** | • Balanced granularity<br>• Predictable daily costs<br>• Good for regular jobs | • May not align with job patterns<br>• Weekend waste potential | Regular ETL jobs |
| **Monthly** | • Simple billing<br>• Volume discounts<br>• Predictable budgeting | • Upfront commitment<br>• Potential waste<br>• Less flexibility | Production workloads |
| **Yearly** | • Maximum discounts<br>• Budget planning<br>• Enterprise friendly | • High upfront cost<br>• Inflexible<br>• Technology lock-in | Enterprise contracts |

**Recommendation:** Support multiple periods with Monthly as default, Daily for variable workloads, Yearly for enterprise discounts.

## Namespace Architecture

### Dedicated CPU Namespace (`dedicated-cpu-ns`)
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-a-quota
  namespace: dedicated-cpu-ns
spec:
  hard:
    requests.cpu: "400"      # 100 units × 4 CPU
    requests.memory: "800Gi" # 100 units × 8GB
    limits.cpu: "400"
    limits.memory: "800Gi"
```

### vCPU Hours Namespace (`vcpu-hours-ns`)
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: shared-pool-quota
  namespace: vcpu-hours-ns
spec:
  hard:
    requests.cpu: "2000"     # Shared pool
    requests.memory: "4000Gi"
    limits.cpu: "2000"
    limits.memory: "4000Gi"
```

### Draft Ingestion Namespace (`draft-ingestion-ns`)
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: draft-quota
  namespace: draft-ingestion-ns
spec:
  hard:
    requests.cpu: "200"      # Smaller allocation for testing
    requests.memory: "400Gi"
```

## Data Model

### Core Entities

```sql
-- Tenants
CREATE TABLE tenants (
    tenant_id UUID PRIMARY KEY,
    tenant_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    status VARCHAR(50) DEFAULT 'active'
);

-- Resource Purchases
CREATE TABLE resource_purchases (
    purchase_id UUID PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(tenant_id),
    resource_type VARCHAR(50) NOT NULL, -- 'dedicated_units', 'vcpu_hours'
    quantity INTEGER NOT NULL,
    time_period VARCHAR(20), -- 'hourly', 'daily', 'monthly', 'yearly'
    valid_from TIMESTAMP NOT NULL,
    valid_until TIMESTAMP NOT NULL,
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Ingestion Jobs
CREATE TABLE ingestion_jobs (
    job_id UUID PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(tenant_id),
    job_name VARCHAR(255) NOT NULL,
    source_type VARCHAR(50) NOT NULL, -- 'postgres', 'mysql', 's3', etc.
    source_config JSONB NOT NULL,
    destination_config JSONB NOT NULL,
    schedule_cron VARCHAR(100),
    resource_requirements JSONB NOT NULL, -- CPU, memory, estimated runtime
    sla_requirements JSONB, -- max_runtime, priority
    status VARCHAR(50) DEFAULT 'draft',
    namespace VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Resource Consumption Tracking
CREATE TABLE resource_consumption (
    consumption_id UUID PRIMARY KEY,
    job_id UUID REFERENCES ingestion_jobs(job_id),
    tenant_id UUID REFERENCES tenants(tenant_id),
    execution_id UUID NOT NULL,
    cpu_seconds INTEGER NOT NULL,
    memory_gb_seconds INTEGER NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NOT NULL,
    namespace VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Capacity Slots (for time-based scheduling)
CREATE TABLE capacity_slots (
    slot_id UUID PRIMARY KEY,
    namespace VARCHAR(100) NOT NULL,
    time_slot TIMESTAMP NOT NULL,
    slot_duration_minutes INTEGER NOT NULL,
    total_cpu_capacity INTEGER NOT NULL,
    total_memory_capacity INTEGER NOT NULL,
    allocated_cpu INTEGER DEFAULT 0,
    allocated_memory INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(namespace, time_slot, slot_duration_minutes)
);

-- Job Executions
CREATE TABLE job_executions (
    execution_id UUID PRIMARY KEY,
    job_id UUID REFERENCES ingestion_jobs(job_id),
    scheduled_time TIMESTAMP NOT NULL,
    actual_start_time TIMESTAMP,
    actual_end_time TIMESTAMP,
    status VARCHAR(50) DEFAULT 'scheduled',
    resource_used JSONB,
    sla_met BOOLEAN,
    error_message TEXT,
    namespace VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);
```

## API Design

### Resource Management APIs

```yaml
# Purchase Resources
POST /api/v1/tenants/{tenant_id}/purchases
{
  "resource_type": "dedicated_units|vcpu_hours",
  "quantity": 100,
  "time_period": "monthly",
  "valid_from": "2024-01-01T00:00:00Z",
  "valid_until": "2024-02-01T00:00:00Z"
}

# Get Resource Usage
GET /api/v1/tenants/{tenant_id}/usage
Response:
{
  "tenant_id": "uuid",
  "current_period": {
    "dedicated_units": {
      "purchased": 100,
      "allocated": 75,
      "available": 25
    },
    "vcpu_hours": {
      "purchased": 1000,
      "consumed": 450,
      "remaining": 550
    }
  }
}
```

### Job Management APIs

```yaml
# Create Ingestion Job
POST /api/v1/tenants/{tenant_id}/jobs
{
  "job_name": "postgres-to-s3-daily",
  "source_type": "postgres",
  "source_config": {
    "host": "pg.example.com",
    "database": "production",
    "table": "orders",
    "credentials_secret": "pg-secret"
  },
  "destination_config": {
    "type": "s3",
    "bucket": "data-lake",
    "path": "/ingestion/orders/",
    "format": "parquet"
  },
  "schedule_cron": "0 2 * * *",
  "resource_requirements": {
    "cpu_cores": 4,
    "memory_gb": 8,
    "estimated_runtime_minutes": 30
  },
  "sla_requirements": {
    "max_runtime_minutes": 60,
    "priority": "medium"
  }
}

# Get Resource Estimation
POST /api/v1/estimation/calculate
{
  "source_type": "postgres",
  "source_config": {...},
  "data_volume_gb": 100,
  "transformation_complexity": "medium"
}
Response:
{
  "estimated_resources": {
    "cpu_cores": 4,
    "memory_gb": 8,
    "runtime_minutes": 25
  },
  "recommended_units": {
    "dedicated_units": 2,
    "vcpu_hours": 2
  },
  "confidence_level": 0.85
}
```

## Capacity Management Algorithm

### Time-Slot Based Scheduling

```python
class CapacityManager:
    def find_available_slot(self, job_requirements, preferred_time):
        """
        Find available capacity slot for job execution
        """
        required_cpu = job_requirements['cpu_cores']
        required_memory = job_requirements['memory_gb']
        estimated_duration = job_requirements['estimated_runtime_minutes']
        
        # Check preferred time slot
        slot = self.get_capacity_slot(preferred_time, estimated_duration)
        
        if slot.available_cpu >= required_cpu and slot.available_memory >= required_memory:
            return slot
        
        # Find next available slot within SLA window
        sla_window = job_requirements.get('sla_window_hours', 24)
        return self.find_next_available_slot(
            preferred_time, 
            sla_window, 
            required_cpu, 
            required_memory,
            estimated_duration
        )
    
    def allocate_resources(self, slot, job_requirements):
        """
        Allocate resources in the selected slot
        """
        slot.allocated_cpu += job_requirements['cpu_cores']
        slot.allocated_memory += job_requirements['memory_gb']
        
        # Update database
        self.update_capacity_slot(slot)
```

### Cross-Namespace Resource Sharing

```python
class CrossNamespaceScheduler:
    def schedule_with_spillover(self, job, tenant_resources):
        """
        Schedule job with spillover to other namespaces during idle periods
        """
        primary_ns = self.get_primary_namespace(tenant_resources.resource_type)
        
        # Try primary namespace first
        slot = self.capacity_manager.find_available_slot(
            job.resource_requirements, 
            job.preferred_time,
            namespace=primary_ns
        )
        
        if slot:
            return self.schedule_job(job, slot, primary_ns)
        
        # Check for idle capacity in other namespaces
        for ns in ['dedicated-cpu-ns', 'vcpu-hours-ns']:
            if ns != primary_ns:
                idle_slot = self.find_idle_capacity(ns, job.preferred_time)
                if idle_slot and self.can_use_idle_capacity(tenant_resources, ns):
                    return self.schedule_job(job, idle_slot, ns)
        
        # Schedule in draft namespace for testing
        return self.schedule_in_draft_namespace(job)
```

## SLA Management and Job Promotion

### Draft Namespace Testing

```python
class SLAManager:
    def evaluate_draft_execution(self, execution):
        """
        Evaluate job performance in draft namespace
        """
        actual_runtime = execution.actual_end_time - execution.actual_start_time
        estimated_runtime = execution.job.resource_requirements['estimated_runtime_minutes']
        
        performance_ratio = actual_runtime.total_seconds() / (estimated_runtime * 60)
        
        if performance_ratio <= 1.2:  # Within 20% of estimate
            return {
                'promotion_eligible': True,
                'recommended_namespace': self.get_target_namespace(execution.job),
                'confidence': 'high'
            }
        elif performance_ratio <= 1.5:  # Within 50% of estimate
            return {
                'promotion_eligible': True,
                'recommended_namespace': self.get_target_namespace(execution.job),
                'confidence': 'medium',
                'resource_adjustment': {
                    'cpu_cores': execution.job.resource_requirements['cpu_cores'] * 1.2,
                    'memory_gb': execution.job.resource_requirements['memory_gb'] * 1.2
                }
            }
        else:
            return {
                'promotion_eligible': False,
                'reason': 'performance_below_threshold',
                'recommended_action': 'increase_resources_or_purchase_more_units'
            }
```

### Promotion Workflow

```python
class JobPromotionService:
    def promote_job(self, job_id, evaluation_result):
        """
        Promote job from draft to production namespace
        """
        job = self.get_job(job_id)
        
        if not evaluation_result['promotion_eligible']:
            return self.send_feedback_to_tenant(job, evaluation_result)
        
        # Update job configuration
        if 'resource_adjustment' in evaluation_result:
            job.resource_requirements.update(evaluation_result['resource_adjustment'])
        
        # Move to target namespace
        target_namespace = evaluation_result['recommended_namespace']
        job.namespace = target_namespace
        job.status = 'active'
        
        # Schedule in production namespace
        self.scheduler.schedule_job(job, target_namespace)
        
        return {
            'status': 'promoted',
            'namespace': target_namespace,
            'updated_requirements': job.resource_requirements
        }
```

## Resource Estimation Engine

### Machine Learning-Based Estimation

```python
class ResourceEstimationEngine:
    def __init__(self):
        self.models = {
            'postgres': self.load_model('postgres_estimation_model'),
            'mysql': self.load_model('mysql_estimation_model'),
            's3': self.load_model('s3_estimation_model')
        }
    
    def estimate_resources(self, job_config):
        """
        Estimate resource requirements based on job configuration
        """
        source_type = job_config['source_type']
        model = self.models.get(source_type)
        
        if not model:
            return self.fallback_estimation(job_config)
        
        features = self.extract_features(job_config)
        prediction = model.predict(features)
        
        return {
            'cpu_cores': max(1, int(prediction['cpu'])),
            'memory_gb': max(2, int(prediction['memory'])),
            'runtime_minutes': max(5, int(prediction['runtime'])),
            'confidence': prediction['confidence']
        }
    
    def extract_features(self, job_config):
        """
        Extract features for ML model
        """
        return {
            'data_volume_gb': self.estimate_data_volume(job_config),
            'table_count': len(job_config.get('tables', [1])),
            'transformation_complexity': self.complexity_score(job_config),
            'source_connection_latency': self.get_connection_metrics(job_config),
            'historical_similar_jobs': self.find_similar_jobs(job_config)
        }
```

### Rule-Based Fallback

```python
class FallbackEstimator:
    RESOURCE_RULES = {
        'postgres': {
            'base_cpu': 2,
            'base_memory': 4,
            'cpu_per_gb': 0.1,
            'memory_per_gb': 0.2,
            'base_runtime_minutes': 10
        },
        's3': {
            'base_cpu': 1,
            'base_memory': 2,
            'cpu_per_gb': 0.05,
            'memory_per_gb': 0.1,
            'base_runtime_minutes': 5
        }
    }
    
    def estimate(self, job_config):
        source_type = job_config['source_type']
        rules = self.RESOURCE_RULES.get(source_type, self.RESOURCE_RULES['postgres'])
        
        estimated_data_gb = job_config.get('estimated_data_gb', 10)
        
        return {
            'cpu_cores': rules['base_cpu'] + (estimated_data_gb * rules['cpu_per_gb']),
            'memory_gb': rules['base_memory'] + (estimated_data_gb * rules['memory_per_gb']),
            'runtime_minutes': rules['base_runtime_minutes'] + (estimated_data_gb * 2),
            'confidence': 0.6
        }
```

## Monitoring and Analytics

### Key Metrics

```python
class MetricsCollector:
    def collect_tenant_metrics(self, tenant_id):
        return {
            'resource_utilization': {
                'dedicated_units_usage_percent': self.get_dedicated_usage(tenant_id),
                'vcpu_hours_consumption_rate': self.get_vcpu_consumption_rate(tenant_id),
                'peak_usage_times': self.get_peak_usage_patterns(tenant_id)
            },
            'job_performance': {
                'average_runtime': self.get_avg_runtime(tenant_id),
                'sla_compliance_rate': self.get_sla_compliance(tenant_id),
                'failure_rate': self.get_failure_rate(tenant_id)
            },
            'cost_efficiency': {
                'cost_per_gb_processed': self.get_cost_efficiency(tenant_id),
                'idle_resource_percentage': self.get_idle_percentage(tenant_id)
            }
        }
```

## Scaling Considerations

### Horizontal Scaling

1. **Database Sharding**: Partition by tenant_id for multi-tenant isolation
2. **Microservices**: Separate services for scheduling, monitoring, billing
3. **Event-Driven Architecture**: Use message queues for job state changes
4. **Caching**: Redis for capacity slot caching and resource calculations

### Performance Optimization

1. **Capacity Slot Pre-computation**: Calculate slots in advance
2. **Resource Pool Management**: Maintain warm pools for quick allocation
3. **Batch Operations**: Group similar jobs for efficient resource usage
4. **Predictive Scaling**: Scale namespaces based on usage patterns

## Implementation Phases

### Phase 1: Core Infrastructure (Months 1-2)
- Basic tenant management
- Resource purchase and tracking
- Simple job scheduling
- Draft namespace testing

### Phase 2: Advanced Features (Months 3-4)
- Cross-namespace resource sharing
- SLA management and promotion
- Basic resource estimation
- Monitoring dashboard

### Phase 3: Intelligence Layer (Months 5-6)
- ML-based resource estimation
- Predictive capacity planning
- Advanced analytics and reporting
- Cost optimization recommendations

### Phase 4: Enterprise Features (Months 7-8)
- Multi-region support
- Advanced security and compliance
- Custom SLA tiers
- Integration APIs for enterprise tools

This design provides a scalable, multi-tenant Spark ingestion service with flexible resource allocation models and intelligent capacity management.
