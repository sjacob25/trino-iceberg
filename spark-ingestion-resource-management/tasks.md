# Implementation Plan

## Overview

This implementation plan breaks down the Spark Ingestion Resource Management System into discrete, actionable coding tasks. The plan follows an incremental approach, building core infrastructure first, then adding capacity management, job scheduling, and advanced features progressively.

## Task List

- [ ] 1. Set up project structure and database foundation
- [ ] 1.1 Initialize project with directory structure for API, services, models, and database migrations
  - Create directory structure: `src/api`, `src/services`, `src/models`, `src/database`, `src/config`, `tests/`
  - Set up Python project with `pyproject.toml` or `requirements.txt` for dependencies (FastAPI, SQLAlchemy, Pydantic, etc.)
  - Configure logging and environment variable management
  - _Requirements: 13.1, 13.4_

- [ ] 1.2 Create PostgreSQL database schema with core tables
  - Write SQL migration scripts for `tenants`, `capacity_purchases`, `ingestion_jobs`, `job_executions`, `namespace_capacity`, `time_slice_allocations`, `resource_estimates` tables
  - Implement database indexes as specified in design document
  - Set up Alembic or similar migration tool for schema versioning
  - _Requirements: 1.1, 2.3, 3.1_

- [ ] 1.3 Implement database models and ORM mappings
  - Create SQLAlchemy models for all entities (Tenant, CapacityPurchase, IngestionJob, JobExecution, etc.)
  - Define relationships between models
  - Implement JSON field serialization for configuration objects
  - _Requirements: 1.1, 2.3, 3.1_

- [ ] 1.4 Set up TimescaleDB extension for time-series metrics
  - Configure TimescaleDB hypertables for `job_executions` and `time_slice_allocations`
  - Implement automatic partitioning and retention policies
  - Create aggregation functions for metrics queries
  - _Requirements: 11.1, 14.5_

- [ ] 2. Implement core domain models and validation
- [ ] 2.1 Create Pydantic models for API request/response schemas
  - Implement schemas for capacity purchase, job configuration, resource estimation requests
  - Add validation rules for cron expressions, resource limits, SLA values
  - Create error response schemas
  - _Requirements: 2.1, 2.2, 3.1, 3.2, 3.3_

- [ ] 2.2 Implement tenant management service
  - Write service class for tenant CRUD operations
  - Implement tenant status management (active, suspended, deleted)
  - Add tenant lookup and validation methods
  - _Requirements: 1.1, 10.1_

- [ ] 2.3 Create capacity purchase domain logic
  - Implement capacity purchase creation with validation
  - Write methods to calculate validity periods (daily, monthly, yearly)
  - Implement capacity balance tracking and updates
  - Add methods to check if tenant has sufficient capacity
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [ ] 3. Build Capacity Manager service
- [ ] 3.1 Implement Spark Unit registry and tracking
  - Create service to register and track Spark Units per namespace
  - Implement methods to calculate total available Ingestion Units
  - Write logic to map Spark Units to CPU/memory values
  - Add namespace capacity update handlers
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [ ] 3.2 Implement capacity allocation engine
  - Write algorithm to allocate Ingestion Units to tenants
  - Implement dedicated vs vCPU hours capacity separation
  - Create methods to prevent over-allocation
  - Add capacity reservation and release logic
  - _Requirements: 1.5, 2.4, 6.3_

- [ ] 3.3 Build vCPU hour consumption tracking
  - Implement real-time vCPU hour calculation based on job execution
  - Write methods to update tenant balances after job completion
  - Create balance depletion estimation logic
  - Add balance threshold checking (20% warning, 0% suspension)
  - _Requirements: 9.1, 9.2, 9.3, 9.5_

- [ ] 3.4 Implement Kubernetes namespace quota management
  - Write Kubernetes client wrapper for ResourceQuota operations
  - Implement methods to create/update namespace quotas based on capacity
  - Add quota enforcement validation
  - Create namespace isolation with network policies
  - _Requirements: 6.3, 10.1, 10.4_

- [ ] 4. Develop time-slice scheduling system
- [ ] 4.1 Implement time slice data structures and calculations
  - Create time slice generator (15-minute intervals, 96 per day)
  - Write algorithm to calculate job time slice requirements
  - Implement partial slice usage calculations for job start/end
  - Add time slice to timestamp conversion utilities
  - _Requirements: 7.1, 7.2_

- [ ] 4.2 Build time slice capacity tracking
  - Implement in-memory cache for time slice allocations (Redis-backed)
  - Write methods to query available capacity per time slice
  - Create capacity reservation and release for time slices
  - Add concurrent access handling with locking
  - _Requirements: 7.3, 7.5_

- [ ] 4.3 Implement schedule validation and conflict detection
  - Write algorithm to expand cron/interval schedules to 30-day execution list
  - Implement capacity validation across all required time slices
  - Create conflict detection for insufficient capacity
  - Add alternative time slot recommendation engine
  - _Requirements: 7.3, 7.4_

- [ ] 4.4 Create schedule persistence and updates
  - Implement database operations for time slice allocations
  - Write methods to handle schedule updates and recalculations
  - Add cleanup for expired time slice allocations
  - Implement 2-second update performance requirement
  - _Requirements: 7.5_

- [ ] 5. Build Job Scheduler service
- [ ] 5.1 Implement job configuration validation and creation
  - Write service methods to validate job configurations
  - Implement source connection validation (PostgreSQL, MySQL, S3)
  - Add target configuration validation
  - Create job persistence with initial "draft" status
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [ ] 5.2 Implement job scheduling logic
  - Write cron expression parser and validator
  - Implement interval-based schedule handler
  - Create job-to-namespace assignment logic based on capacity type
  - Add integration with time slice capacity validation
  - _Requirements: 3.2, 6.1, 6.2, 6.5_

- [ ] 5.3 Build job lifecycle management
  - Implement job status transitions (draft → active → paused → deleted)
  - Write methods for job updates and schedule modifications
  - Add job deletion with cleanup of allocations
  - Create job query and filtering methods
  - _Requirements: 3.5, 13.2_

- [ ] 5.4 Implement fair queuing for vCPU Hours namespace
  - Write fair share calculation based on purchased vCPU hours
  - Implement consumption tracking vs fair share
  - Create weighted priority queue for job admission
  - Add tenant monopolization prevention logic
  - _Requirements: 10.2, 10.3_

- [ ] 6. Develop Spark job execution integration
- [ ] 6.1 Create Spark job submission wrapper
  - Implement Kubernetes SparkApplication CRD client
  - Write methods to generate Spark job configurations from ingestion jobs
  - Add source-specific Spark job templates (PostgreSQL, MySQL, S3)
  - Implement job submission to appropriate namespace
  - _Requirements: 3.1, 5.1, 6.1, 6.2_

- [ ] 6.2 Build job execution monitoring
  - Implement Kubernetes pod/job status monitoring
  - Write metrics collection from Spark application metrics
  - Add CPU and memory usage tracking
  - Create execution duration and data volume tracking
  - _Requirements: 5.2, 11.1_

- [ ] 6.3 Implement job execution state management
  - Write methods to track job execution lifecycle (pending → running → completed/failed)
  - Implement execution record persistence
  - Add error capture and logging
  - Create execution history queries
  - _Requirements: 11.1, 13.3_

- [ ] 7. Build Draft Namespace profiling system
- [ ] 7.1 Implement draft namespace job placement
  - Write logic to route new jobs to draft namespace
  - Implement draft run counter (default N=3)
  - Add draft namespace resource allocation
  - Create draft execution tracking
  - _Requirements: 5.1, 6.4_

- [ ] 7.2 Build metrics collection and SLA validation
  - Implement detailed metrics collection for draft runs
  - Write SLA compliance checker (actual vs expected duration)
  - Add resource utilization analysis (60-90% target)
  - Create metrics aggregation across multiple runs
  - _Requirements: 5.2, 5.3_

- [ ] 7.3 Implement job promotion logic
  - Write promotion criteria validator (N successful runs, SLA met)
  - Implement automatic promotion to production namespace
  - Add promotion notification to tenants
  - Create promotion audit trail
  - _Requirements: 5.5, 6.4_

- [ ] 7.4 Build feedback and recommendation engine
  - Implement SLA violation detection and notification
  - Write resource adjustment recommendations (increase/decrease)
  - Add cost impact analysis for recommendations
  - Create feedback delivery mechanism
  - _Requirements: 5.4, 11.3_

- [ ] 8. Implement Resource Estimator service
- [ ] 8.1 Create estimation algorithm core
  - Implement base throughput rate calculations per source type
  - Write complexity factor calculation based on schema characteristics
  - Add required cores and memory estimation logic
  - Implement Ingestion Unit mapping
  - _Requirements: 4.1, 4.2_

- [ ] 8.2 Build cost comparison calculator
  - Implement dedicated unit cost calculation
  - Write vCPU hours cost calculation with execution frequency
  - Add monthly/yearly cost projections
  - Create cost comparison and recommendation logic
  - _Requirements: 4.4_

- [ ] 8.3 Implement historical data analysis
  - Write queries to fetch similar job performance data
  - Implement job clustering by characteristics
  - Add confidence score calculation based on historical data
  - Create fallback conservative estimates when no history exists
  - _Requirements: 4.2, 4.3_

- [ ] 8.4 Build continuous learning feedback loop
  - Implement actual vs estimated metrics comparison
  - Write model update logic based on new execution data
  - Add estimation accuracy tracking
  - Create model refinement for job profiles
  - _Requirements: 4.5_

- [ ] 9. Develop opportunistic scheduling system
- [ ] 9.1 Implement idle capacity detection
  - Write real-time namespace utilization monitoring
  - Implement idle threshold detection (20% for 5 minutes)
  - Add idle capacity calculation and expiration
  - Create idle capacity advertisement to scheduler
  - _Requirements: 8.1, 8.2_

- [ ] 9.2 Build opportunistic job placement
  - Implement logic to place vCPU jobs in idle dedicated capacity
  - Write preemptible job marking
  - Add opportunistic execution tracking (no vCPU hour charges)
  - Create opportunistic capacity allocation prioritization
  - _Requirements: 8.3, 8.5_

- [ ] 9.3 Implement preemption handling
  - Write preemption trigger when dedicated job needs resources
  - Implement graceful job termination (SIGTERM, 30s grace)
  - Add job requeue logic to vCPU Hours namespace
  - Create preemption count tracking and alerting
  - _Requirements: 8.4_

- [ ]* 9.4 Add job checkpointing support
  - Implement checkpoint state capture before preemption
  - Write checkpoint restoration logic on requeue
  - Add checkpoint storage management
  - Create checkpoint-aware job resume
  - _Requirements: 8.4_

- [ ] 10. Build REST API layer
- [ ] 10.1 Implement capacity management endpoints
  - Create POST `/api/v1/tenants/{tenant_id}/capacity/purchase` endpoint
  - Implement GET `/api/v1/tenants/{tenant_id}/capacity/balance` endpoint
  - Add request validation and error handling
  - Write API response formatting
  - _Requirements: 2.1, 2.2, 2.3, 13.1_

- [ ] 10.2 Create job management endpoints
  - Implement POST `/api/v1/tenants/{tenant_id}/jobs` endpoint
  - Create GET `/api/v1/tenants/{tenant_id}/jobs/{job_id}` endpoint
  - Add PATCH `/api/v1/tenants/{tenant_id}/jobs/{job_id}/schedule` endpoint
  - Implement DELETE `/api/v1/tenants/{tenant_id}/jobs/{job_id}` endpoint
  - _Requirements: 3.1, 3.2, 13.2_

- [ ] 10.3 Build resource estimation endpoint
  - Create POST `/api/v1/tenants/{tenant_id}/estimate` endpoint
  - Implement request validation for estimation parameters
  - Add response formatting with cost comparison
  - Write error handling for estimation failures
  - _Requirements: 4.1, 4.2, 4.4, 13.1_

- [ ] 10.4 Implement monitoring and metrics endpoints
  - Create GET `/api/v1/tenants/{tenant_id}/jobs/{job_id}/executions` endpoint
  - Implement GET `/api/v1/tenants/{tenant_id}/utilization` endpoint
  - Add GET `/api/v1/tenants/{tenant_id}/capacity/available-slots` endpoint
  - Write pagination and filtering support
  - _Requirements: 11.1, 11.4, 13.3_

- [ ] 10.5 Add authentication and authorization middleware
  - Implement OAuth 2.0 JWT token validation
  - Write role-based access control (RBAC) middleware
  - Add tenant-scoped permission checking
  - Create API key authentication for service accounts
  - _Requirements: 13.4_

- [ ] 10.6 Implement rate limiting and request throttling
  - Write rate limiter middleware (100 req/min standard, 500 req/min premium)
  - Add burst allowance handling (2x for 10 seconds)
  - Implement rate limit headers in responses
  - Create rate limit exceeded error responses
  - _Requirements: 13.5_

- [ ] 11. Build Monitoring Service
- [ ] 11.1 Implement metrics collection system
  - Create metrics collector for job executions
  - Write CPU, memory, duration, data volume tracking
  - Implement TimescaleDB metrics persistence
  - Add metrics aggregation and downsampling
  - _Requirements: 11.1, 11.2_

- [ ] 11.2 Build alerting system
  - Implement SLA violation detection and alerts
  - Write capacity exhaustion alerts (80%, 95%, 100%)
  - Add vCPU hour balance alerts (20% threshold)
  - Create alert delivery mechanism (email, webhook)
  - _Requirements: 9.3, 11.5_

- [ ] 11.3 Create efficiency metrics calculator
  - Implement resource utilization efficiency calculations
  - Write underutilization detection (<60% usage)
  - Add optimization recommendations
  - Create efficiency trend analysis
  - _Requirements: 11.2, 11.3_

- [ ] 11.4 Build capacity forecasting engine
  - Implement historical utilization analysis (30-day rolling window)
  - Write growth rate calculation per tenant
  - Add 30/60/90-day capacity forecasts
  - Create forecast-based Spark Unit purchase recommendations
  - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5_

- [ ] 12. Implement Job Promoter service
- [ ] 12.1 Create draft job monitoring daemon
  - Implement background worker to monitor draft namespace jobs
  - Write draft run completion detection
  - Add promotion criteria evaluation
  - Create promotion trigger logic
  - _Requirements: 5.5, 6.4_

- [ ] 12.2 Build promotion execution workflow
  - Implement job namespace migration logic
  - Write production namespace capacity validation
  - Add job configuration updates for production
  - Create promotion audit logging
  - _Requirements: 6.4, 6.5_

- [ ] 12.3 Implement promotion notification system
  - Write tenant notification for successful promotions
  - Add failure notifications with recommendations
  - Implement notification templates
  - Create notification delivery tracking
  - _Requirements: 5.4, 5.5_

- [ ] 13. Add error handling and resilience
- [ ] 13.1 Implement comprehensive error handling
  - Create custom exception classes for all error categories
  - Write error response formatters with details and alternatives
  - Add request ID tracking for debugging
  - Implement structured error logging
  - _Requirements: 13.5_

- [ ] 13.2 Build retry and recovery mechanisms
  - Implement exponential backoff for transient errors
  - Write job requeue logic for failures
  - Add circuit breaker for external service calls
  - Create dead letter queue for failed jobs
  - _Requirements: 14.1_

- [ ] 13.3 Add database transaction management
  - Implement transaction boundaries for critical operations
  - Write rollback handlers for capacity allocations
  - Add optimistic locking for concurrent updates
  - Create transaction retry logic for deadlocks
  - _Requirements: 1.5, 2.3_

- [ ] 14. Implement caching layer
- [ ] 14.1 Set up Redis for distributed caching
  - Configure Redis connection and client
  - Implement cache key naming conventions
  - Add cache TTL management
  - Create cache invalidation strategies
  - _Requirements: 14.3_

- [ ] 14.2 Build capacity state caching
  - Implement in-memory cache for namespace capacity
  - Write cache update on capacity changes
  - Add cache-aside pattern for capacity queries
  - Create cache warming on service startup
  - _Requirements: 7.5, 14.4_

- [ ] 14.3 Add time slice allocation caching
  - Implement Redis-backed time slice cache
  - Write cache update on schedule changes
  - Add distributed locking for cache updates
  - Create cache expiration for past time slices
  - _Requirements: 7.5_

- [ ] 15. Build deployment and infrastructure code
- [ ] 15.1 Create Kubernetes deployment manifests
  - Write Deployment manifests for API servers, Capacity Manager, Job Scheduler, Job Promoter
  - Implement Service definitions for internal communication
  - Add ConfigMaps for configuration management
  - Create Secrets for sensitive data (DB credentials, API keys)
  - _Requirements: 14.1, 14.2_

- [ ] 15.2 Implement Kubernetes namespace setup
  - Write scripts to create draft, dedicated-cpu, vcpu-hours namespaces
  - Implement ResourceQuota templates
  - Add LimitRange configurations
  - Create NetworkPolicy definitions for isolation
  - _Requirements: 6.3, 10.4_

- [ ] 15.3 Create database migration scripts
  - Write initial schema migration
  - Implement rollback scripts
  - Add seed data for testing
  - Create migration execution automation
  - _Requirements: 1.1, 1.2_

- [ ] 15.4 Build Docker images and CI/CD pipeline
  - Create Dockerfiles for all services
  - Write multi-stage builds for optimization
  - Implement CI pipeline for testing and building
  - Add CD pipeline for deployment automation
  - _Requirements: 14.1_

- [ ]* 15.5 Set up monitoring and observability infrastructure
  - Deploy Prometheus for metrics collection
  - Configure Grafana dashboards
  - Set up ELK stack or CloudWatch for logging
  - Create alerting rules and notification channels
  - _Requirements: 11.4, 11.5_

- [ ] 16. Implement integration tests
- [ ] 16.1 Create end-to-end job lifecycle tests
  - Write test for job creation → draft execution → promotion → production execution
  - Implement metrics validation in tests
  - Add SLA compliance verification
  - Create test data cleanup
  - _Requirements: 5.1, 5.2, 5.3, 5.5_

- [ ] 16.2 Build capacity management integration tests
  - Write test for capacity purchase → allocation → consumption → exhaustion
  - Implement dedicated and vCPU hours model tests
  - Add balance tracking validation
  - Create capacity limit enforcement tests
  - _Requirements: 2.1, 2.2, 2.3, 2.5, 9.5_

- [ ] 16.3 Implement multi-tenant isolation tests
  - Write tests for concurrent job submissions from multiple tenants
  - Implement resource quota enforcement validation
  - Add fair scheduling verification
  - Create tenant data isolation tests
  - _Requirements: 10.1, 10.2, 10.3, 10.4_

- [ ] 16.4 Create opportunistic scheduling tests
  - Write test for idle capacity detection → opportunistic placement → preemption
  - Implement preemption and requeue validation
  - Add vCPU hour charge verification (no charge for opportunistic)
  - Create preemption count tracking tests
  - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [ ] 16.5 Build time slice scheduling tests
  - Write tests for schedule validation and conflict detection
  - Implement alternative slot recommendation validation
  - Add capacity reservation and release tests
  - Create concurrent schedule update tests
  - _Requirements: 7.2, 7.3, 7.4, 7.5_

- [ ]* 17. Performance optimization and load testing
- [ ]* 17.1 Implement API performance optimizations
  - Profile API endpoints and identify bottlenecks
  - Add database query optimization (indexes, query plans)
  - Implement connection pooling tuning
  - Create response caching for read-heavy endpoints
  - _Requirements: 13.5, 14.3_

- [ ]* 17.2 Build load testing suite
  - Create load test scenarios for 500 concurrent jobs
  - Implement 100 tenant simulation
  - Add API throughput tests (50 req/sec target)
  - Write time slice calculation performance tests (<10 sec for 30 days)
  - _Requirements: 14.1, 14.2, 14.3, 14.4_

- [ ]* 17.3 Optimize time slice calculations
  - Profile time slice algorithm performance
  - Implement batch processing for schedule expansions
  - Add parallel processing for capacity validations
  - Create performance benchmarks
  - _Requirements: 7.5, 14.4_

- [ ]* 18. Documentation and operational guides
- [ ]* 18.1 Create API documentation
  - Write OpenAPI/Swagger specification
  - Generate interactive API documentation
  - Add code examples for common use cases
  - Create authentication setup guide
  - _Requirements: 13.1, 13.2, 13.3_

- [ ]* 18.2 Write operational runbooks
  - Create capacity planning guide
  - Write incident response procedures
  - Add database backup and restore procedures
  - Create scaling and performance tuning guide
  - _Requirements: 12.5, 14.1, 14.2_

- [ ]* 18.3 Build tenant onboarding documentation
  - Write getting started guide
  - Create capacity model selection guide
  - Add job configuration examples
  - Write troubleshooting guide
  - _Requirements: 2.1, 2.2, 3.1, 4.1_
