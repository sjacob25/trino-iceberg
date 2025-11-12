# Spark Ingestion Service: API Specification

## API Overview

The Spark Ingestion Service provides RESTful APIs for managing multi-tenant data ingestion workflows with flexible resource allocation models.

**Base URL:** `https://api.spark-ingestion.company.com/v1`

**Authentication:** Bearer token (JWT) with tenant context

## Resource Management APIs

### Purchase Resources

**Endpoint:** `POST /tenants/{tenant_id}/purchases`

**Description:** Purchase ingestion resources for a tenant

```yaml
Request:
{
  "resource_type": "dedicated_units|vcpu_hours",
  "quantity": 100,
  "time_period": "hourly|daily|monthly|yearly",
  "valid_from": "2024-01-01T00:00:00Z",
  "valid_until": "2024-02-01T00:00:00Z",
  "auto_renewal": true,
  "billing_metadata": {
    "cost_center": "engineering",
    "project_code": "data-platform"
  }
}

Response (201 Created):
{
  "purchase_id": "uuid",
  "tenant_id": "uuid",
  "resource_type": "dedicated_units",
  "quantity": 100,
  "time_period": "monthly",
  "valid_from": "2024-01-01T00:00:00Z",
  "valid_until": "2024-02-01T00:00:00Z",
  "status": "active",
  "total_cost": 5000.00,
  "currency": "USD",
  "created_at": "2024-01-01T10:00:00Z"
}
```

### Get Resource Usage

**Endpoint:** `GET /tenants/{tenant_id}/usage`

**Query Parameters:**
- `period`: `current|last_30_days|last_90_days`
- `resource_type`: `dedicated_units|vcpu_hours|all`

```yaml
Response (200 OK):
{
  "tenant_id": "uuid",
  "period": "current",
  "usage_summary": {
    "dedicated_units": {
      "purchased": 100,
      "allocated": 75,
      "available": 25,
      "utilization_percentage": 75.0
    },
    "vcpu_hours": {
      "purchased": 1000,
      "consumed": 450,
      "remaining": 550,
      "consumption_rate_per_day": 15.5
    }
  },
  "cost_summary": {
    "total_spent": 2250.00,
    "projected_monthly_cost": 4500.00,
    "cost_per_gb_processed": 0.25
  },
  "recommendations": [
    {
      "type": "cost_optimization",
      "message": "Consider switching to vcpu_hours model for 20% cost savings",
      "potential_savings": 900.00
    }
  ]
}
```

### Modify Resource Allocation

**Endpoint:** `PATCH /tenants/{tenant_id}/purchases/{purchase_id}`

```yaml
Request:
{
  "quantity": 150,
  "auto_renewal": false
}

Response (200 OK):
{
  "purchase_id": "uuid",
  "previous_quantity": 100,
  "new_quantity": 150,
  "effective_date": "2024-01-15T00:00:00Z",
  "prorated_cost": 1250.00
}
```

## Job Management APIs

### Create Ingestion Job

**Endpoint:** `POST /tenants/{tenant_id}/jobs`

```yaml
Request:
{
  "job_name": "postgres-to-s3-daily",
  "description": "Daily ingestion of orders table",
  "source_type": "postgres",
  "source_config": {
    "host": "pg.example.com",
    "port": 5432,
    "database": "production",
    "schema": "public",
    "table": "orders",
    "credentials_secret": "pg-secret",
    "connection_pool_size": 5,
    "query_timeout_seconds": 300,
    "incremental_column": "updated_at",
    "incremental_strategy": "append"
  },
  "destination_config": {
    "type": "s3",
    "bucket": "data-lake-prod",
    "path": "/ingestion/orders/year={year}/month={month}/day={day}/",
    "format": "parquet",
    "compression": "snappy",
    "partition_columns": ["year", "month", "day"],
    "write_mode": "overwrite"
  },
  "transformation_config": {
    "sql_transformations": [
      "SELECT *, CURRENT_TIMESTAMP as ingestion_timestamp FROM source_table",
      "WHERE updated_at >= '{last_run_time}'"
    ],
    "data_quality_rules": [
      {
        "column": "order_id",
        "rule": "not_null",
        "action": "fail"
      },
      {
        "column": "amount",
        "rule": "greater_than",
        "value": 0,
        "action": "warn"
      }
    ]
  },
  "schedule_config": {
    "cron": "0 2 * * *",
    "timezone": "UTC",
    "max_concurrent_runs": 1,
    "catchup": false,
    "retry_policy": {
      "max_retries": 3,
      "retry_delay_seconds": 300,
      "exponential_backoff": true
    }
  },
  "resource_requirements": {
    "cpu_cores": 4,
    "memory_gb": 8,
    "estimated_runtime_minutes": 30,
    "disk_gb": 20
  },
  "sla_requirements": {
    "max_runtime_minutes": 60,
    "priority": "medium",
    "notification_channels": ["email", "slack"],
    "escalation_policy": "on_call_team"
  },
  "tags": {
    "team": "data-engineering",
    "environment": "production",
    "data_classification": "internal"
  }
}

Response (201 Created):
{
  "job_id": "uuid",
  "tenant_id": "uuid",
  "job_name": "postgres-to-s3-daily",
  "status": "draft",
  "namespace": "draft-ingestion-ns",
  "estimated_cost_per_run": 2.50,
  "next_scheduled_run": "2024-01-02T02:00:00Z",
  "created_at": "2024-01-01T10:00:00Z",
  "validation_results": {
    "source_connectivity": "passed",
    "destination_permissions": "passed",
    "resource_availability": "passed",
    "warnings": [
      "Estimated runtime may exceed 80% of SLA limit"
    ]
  }
}
```

### List Jobs

**Endpoint:** `GET /tenants/{tenant_id}/jobs`

**Query Parameters:**
- `status`: `draft|active|paused|failed|archived`
- `source_type`: `postgres|mysql|s3|...`
- `page`: Page number (default: 1)
- `limit`: Items per page (default: 20, max: 100)
- `sort`: `created_at|name|last_run|next_run`
- `order`: `asc|desc`

```yaml
Response (200 OK):
{
  "jobs": [
    {
      "job_id": "uuid",
      "job_name": "postgres-to-s3-daily",
      "status": "active",
      "source_type": "postgres",
      "namespace": "dedicated-cpu-ns",
      "last_run": {
        "execution_id": "uuid",
        "start_time": "2024-01-01T02:00:00Z",
        "end_time": "2024-01-01T02:25:00Z",
        "status": "completed",
        "records_processed": 150000,
        "data_volume_gb": 2.5
      },
      "next_run": "2024-01-02T02:00:00Z",
      "sla_compliance": {
        "last_30_days": 96.7,
        "trend": "stable"
      }
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total_items": 45,
    "total_pages": 3
  }
}
```

### Get Job Details

**Endpoint:** `GET /tenants/{tenant_id}/jobs/{job_id}`

```yaml
Response (200 OK):
{
  "job_id": "uuid",
  "tenant_id": "uuid",
  "job_name": "postgres-to-s3-daily",
  "status": "active",
  "namespace": "dedicated-cpu-ns",
  "source_config": { ... },
  "destination_config": { ... },
  "resource_requirements": { ... },
  "sla_requirements": { ... },
  "performance_metrics": {
    "average_runtime_minutes": 28.5,
    "success_rate_percentage": 98.2,
    "average_records_per_minute": 5263,
    "cost_per_run": 2.35
  },
  "recent_executions": [
    {
      "execution_id": "uuid",
      "start_time": "2024-01-01T02:00:00Z",
      "end_time": "2024-01-01T02:25:00Z",
      "status": "completed",
      "records_processed": 150000,
      "resource_usage": {
        "cpu_seconds": 7200,
        "memory_gb_seconds": 14400,
        "actual_cost": 2.35
      }
    }
  ]
}
```

### Update Job

**Endpoint:** `PATCH /tenants/{tenant_id}/jobs/{job_id}`

```yaml
Request:
{
  "schedule_config": {
    "cron": "0 1 * * *"
  },
  "resource_requirements": {
    "cpu_cores": 6,
    "memory_gb": 12
  }
}

Response (200 OK):
{
  "job_id": "uuid",
  "updated_fields": ["schedule_config", "resource_requirements"],
  "validation_results": {
    "resource_availability": "passed",
    "schedule_conflicts": "none"
  },
  "effective_date": "2024-01-02T00:00:00Z"
}
```

### Control Job Execution

**Endpoint:** `POST /tenants/{tenant_id}/jobs/{job_id}/actions`

```yaml
# Pause Job
Request:
{
  "action": "pause",
  "reason": "Maintenance window"
}

# Resume Job
Request:
{
  "action": "resume"
}

# Trigger Manual Run
Request:
{
  "action": "trigger",
  "parameters": {
    "override_schedule": true,
    "priority": "high"
  }
}

Response (200 OK):
{
  "job_id": "uuid",
  "action": "pause",
  "status": "paused",
  "execution_id": "uuid", # for trigger action
  "message": "Job paused successfully"
}
```

## Resource Estimation APIs

### Calculate Resource Estimation

**Endpoint:** `POST /estimation/calculate`

```yaml
Request:
{
  "source_type": "postgres",
  "source_config": {
    "host": "pg.example.com",
    "database": "production",
    "table": "orders"
  },
  "data_characteristics": {
    "estimated_rows": 1000000,
    "estimated_size_gb": 5.2,
    "columns_count": 25,
    "has_indexes": true
  },
  "transformation_complexity": "medium",
  "destination_type": "s3",
  "historical_context": {
    "similar_jobs": ["job-uuid-1", "job-uuid-2"],
    "tenant_performance_profile": "high_throughput"
  }
}

Response (200 OK):
{
  "estimation_id": "uuid",
  "estimated_resources": {
    "cpu_cores": 4,
    "memory_gb": 8,
    "runtime_minutes": 25,
    "disk_gb": 15
  },
  "confidence_metrics": {
    "overall_confidence": 0.85,
    "factors": {
      "historical_data_availability": 0.9,
      "source_similarity": 0.8,
      "data_volume_accuracy": 0.85
    }
  },
  "cost_estimation": {
    "dedicated_units": {
      "units_required": 2,
      "cost_per_run": 3.20
    },
    "vcpu_hours": {
      "hours_required": 1.67,
      "cost_per_run": 2.85
    }
  },
  "recommendations": [
    {
      "type": "optimization",
      "message": "Consider partitioning by date column for better performance",
      "potential_improvement": "20% faster execution"
    },
    {
      "type": "cost",
      "message": "vcpu_hours model recommended for this workload pattern",
      "savings": "11% cost reduction"
    }
  ],
  "alternative_configurations": [
    {
      "cpu_cores": 2,
      "memory_gb": 6,
      "runtime_minutes": 40,
      "cost_difference": "-25%",
      "trade_off": "Lower cost, longer runtime"
    }
  ]
}
```

### Get Estimation History

**Endpoint:** `GET /tenants/{tenant_id}/estimations`

```yaml
Response (200 OK):
{
  "estimations": [
    {
      "estimation_id": "uuid",
      "created_at": "2024-01-01T10:00:00Z",
      "source_type": "postgres",
      "estimated_resources": { ... },
      "actual_job_id": "uuid", # if estimation was used
      "accuracy_score": 0.92 # if actual execution data available
    }
  ]
}
```

## Monitoring and Analytics APIs

### Get Tenant Dashboard

**Endpoint:** `GET /tenants/{tenant_id}/dashboard`

```yaml
Response (200 OK):
{
  "tenant_id": "uuid",
  "summary": {
    "active_jobs": 15,
    "total_executions_today": 45,
    "success_rate_24h": 98.2,
    "resource_utilization": 78.5
  },
  "resource_usage": {
    "current_period": {
      "dedicated_units_used": 75,
      "vcpu_hours_consumed": 450,
      "cost_to_date": 2250.00
    },
    "trends": {
      "usage_trend_7d": "increasing",
      "cost_trend_30d": "stable",
      "efficiency_trend": "improving"
    }
  },
  "job_performance": {
    "avg_runtime_minutes": 32.5,
    "sla_compliance_rate": 96.8,
    "top_performing_jobs": [
      {
        "job_id": "uuid",
        "job_name": "mysql-to-s3-hourly",
        "efficiency_score": 95.2
      }
    ],
    "jobs_needing_attention": [
      {
        "job_id": "uuid",
        "job_name": "postgres-large-table",
        "issue": "consistently_exceeding_sla",
        "recommendation": "increase_resources"
      }
    ]
  },
  "alerts": [
    {
      "alert_id": "uuid",
      "severity": "warning",
      "message": "Job 'postgres-to-s3-daily' runtime increased by 40% in last 3 runs",
      "created_at": "2024-01-01T08:30:00Z"
    }
  ]
}
```

### Get Detailed Analytics

**Endpoint:** `GET /tenants/{tenant_id}/analytics`

**Query Parameters:**
- `metric`: `cost|performance|utilization|sla`
- `period`: `1d|7d|30d|90d`
- `granularity`: `hour|day|week|month`
- `job_ids`: Comma-separated list of job IDs

```yaml
Response (200 OK):
{
  "tenant_id": "uuid",
  "metric": "performance",
  "period": "30d",
  "data_points": [
    {
      "timestamp": "2024-01-01T00:00:00Z",
      "avg_runtime_minutes": 28.5,
      "success_rate": 98.2,
      "jobs_executed": 45
    }
  ],
  "aggregated_metrics": {
    "total_executions": 1350,
    "total_data_processed_gb": 2750.5,
    "average_cost_per_gb": 0.82,
    "peak_utilization_time": "02:00-04:00 UTC"
  },
  "comparisons": {
    "vs_previous_period": {
      "runtime_change": "+5.2%",
      "cost_change": "-2.1%",
      "success_rate_change": "+0.8%"
    },
    "vs_tenant_average": {
      "efficiency_percentile": 78,
      "cost_efficiency_percentile": 85
    }
  }
}
```

## System Management APIs

### Get System Status

**Endpoint:** `GET /system/status`

```yaml
Response (200 OK):
{
  "system_status": "healthy",
  "version": "1.2.3",
  "uptime_seconds": 2592000,
  "namespaces": {
    "dedicated-cpu-ns": {
      "status": "healthy",
      "total_capacity": {
        "cpu_cores": 1000,
        "memory_gb": 2000
      },
      "allocated_capacity": {
        "cpu_cores": 750,
        "memory_gb": 1500
      },
      "utilization_percentage": 75.0
    },
    "vcpu-hours-ns": {
      "status": "healthy",
      "total_capacity": {
        "cpu_cores": 2000,
        "memory_gb": 4000
      },
      "current_usage": {
        "cpu_cores": 450,
        "memory_gb": 900
      },
      "utilization_percentage": 22.5
    }
  },
  "queue_status": {
    "pending_jobs": 12,
    "running_jobs": 45,
    "average_wait_time_minutes": 2.5
  }
}
```

### Get Capacity Information

**Endpoint:** `GET /capacity/availability`

**Query Parameters:**
- `namespace`: `dedicated-cpu-ns|vcpu-hours-ns|all`
- `time_window`: ISO 8601 duration (e.g., `PT2H` for 2 hours)
- `start_time`: ISO 8601 timestamp

```yaml
Response (200 OK):
{
  "capacity_windows": [
    {
      "start_time": "2024-01-01T14:00:00Z",
      "end_time": "2024-01-01T16:00:00Z",
      "namespace": "dedicated-cpu-ns",
      "available_capacity": {
        "cpu_cores": 200,
        "memory_gb": 400
      },
      "utilization_forecast": 65.0
    }
  ],
  "recommendations": [
    {
      "message": "High availability window detected between 14:00-16:00 UTC",
      "suggested_action": "Schedule non-critical jobs during this period"
    }
  ]
}
```

## Error Responses

### Standard Error Format

```yaml
{
  "error": {
    "code": "RESOURCE_INSUFFICIENT",
    "message": "Insufficient resources available for job execution",
    "details": {
      "required_cpu": 8,
      "available_cpu": 4,
      "namespace": "dedicated-cpu-ns"
    },
    "suggestions": [
      "Reduce resource requirements",
      "Purchase additional dedicated units",
      "Schedule job during off-peak hours"
    ],
    "request_id": "uuid",
    "timestamp": "2024-01-01T10:00:00Z"
  }
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `TENANT_NOT_FOUND` | 404 | Tenant does not exist |
| `INSUFFICIENT_RESOURCES` | 409 | Not enough resources available |
| `INVALID_SCHEDULE` | 400 | Invalid cron expression |
| `SOURCE_UNREACHABLE` | 422 | Cannot connect to data source |
| `QUOTA_EXCEEDED` | 429 | Resource quota exceeded |
| `JOB_CONFLICT` | 409 | Job name already exists |
| `SLA_VIOLATION` | 422 | Configuration violates SLA requirements |
| `ESTIMATION_FAILED` | 500 | Resource estimation service unavailable |

## Rate Limiting

- **Standard APIs**: 1000 requests per hour per tenant
- **Estimation APIs**: 100 requests per hour per tenant
- **System APIs**: 10 requests per minute per client

Rate limit headers included in all responses:
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1641024000
```

## Webhooks

### Job Status Notifications

Configure webhook endpoints to receive job status updates:

```yaml
POST /tenants/{tenant_id}/webhooks
{
  "url": "https://your-app.com/webhooks/job-status",
  "events": ["job.completed", "job.failed", "job.sla_violated"],
  "secret": "webhook-secret-key"
}

# Webhook payload example
{
  "event": "job.completed",
  "timestamp": "2024-01-01T02:25:00Z",
  "data": {
    "job_id": "uuid",
    "execution_id": "uuid",
    "tenant_id": "uuid",
    "job_name": "postgres-to-s3-daily",
    "status": "completed",
    "runtime_minutes": 25,
    "records_processed": 150000,
    "resource_usage": {
      "cpu_seconds": 7200,
      "memory_gb_seconds": 14400
    }
  }
}
```

This API specification provides comprehensive coverage of all major functionality for the Spark Ingestion Service, including resource management, job lifecycle, monitoring, and system administration.
