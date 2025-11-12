# Resource Estimation and Capacity Management: Deep Dive

## Overview

This document provides detailed technical specifications for the resource estimation engine and capacity management system that powers the Spark Ingestion Service.

## Resource Estimation Engine Architecture

### Multi-Model Approach

```python
class ResourceEstimationEngine:
    def __init__(self):
        self.models = {
            'ml_models': {
                'postgres': MLModel('postgres_v2.pkl'),
                'mysql': MLModel('mysql_v2.pkl'),
                's3': MLModel('s3_v2.pkl'),
                'generic': MLModel('generic_v1.pkl')
            },
            'rule_based': RuleBasedEstimator(),
            'similarity_based': SimilarityEstimator(),
            'hybrid': HybridEstimator()
        }
        
    def estimate(self, job_config, estimation_strategy='hybrid'):
        """
        Multi-strategy resource estimation
        """
        strategies = {
            'ml_only': self._ml_estimation,
            'rule_based': self._rule_based_estimation,
            'similarity': self._similarity_estimation,
            'hybrid': self._hybrid_estimation
        }
        
        return strategies[estimation_strategy](job_config)
```

### Machine Learning Models

#### Feature Engineering

```python
class FeatureExtractor:
    def extract_features(self, job_config):
        """
        Extract comprehensive features for ML models
        """
        base_features = self._extract_base_features(job_config)
        source_features = self._extract_source_features(job_config)
        transformation_features = self._extract_transformation_features(job_config)
        historical_features = self._extract_historical_features(job_config)
        
        return {
            **base_features,
            **source_features,
            **transformation_features,
            **historical_features
        }
    
    def _extract_base_features(self, job_config):
        return {
            'estimated_data_volume_gb': self._estimate_data_volume(job_config),
            'table_count': len(job_config.get('tables', [1])),
            'column_count': self._estimate_column_count(job_config),
            'has_joins': self._has_joins(job_config),
            'has_aggregations': self._has_aggregations(job_config),
            'parallelism_factor': self._calculate_parallelism(job_config)
        }
    
    def _extract_source_features(self, job_config):
        source_type = job_config['source_type']
        
        if source_type in ['postgres', 'mysql']:
            return self._extract_db_features(job_config)
        elif source_type == 's3':
            return self._extract_s3_features(job_config)
        else:
            return self._extract_generic_features(job_config)
    
    def _extract_db_features(self, job_config):
        return {
            'connection_pool_size': job_config.get('connection_pool_size', 5),
            'has_indexes': self._check_indexes(job_config),
            'query_complexity_score': self._calculate_query_complexity(job_config),
            'incremental_load': job_config.get('incremental_strategy') is not None,
            'estimated_network_latency_ms': self._estimate_network_latency(job_config)
        }
    
    def _extract_s3_features(self, job_config):
        return {
            'file_count': self._estimate_file_count(job_config),
            'file_format': job_config.get('format', 'parquet'),
            'compression_type': job_config.get('compression', 'none'),
            'partition_count': self._estimate_partitions(job_config),
            's3_region_latency': self._get_s3_latency(job_config)
        }
```

#### Model Training Pipeline

```python
class ModelTrainer:
    def train_source_specific_model(self, source_type, training_data):
        """
        Train ML model for specific source type
        """
        # Feature preprocessing
        features = self._preprocess_features(training_data)
        
        # Multi-target regression (CPU, Memory, Runtime)
        model = MultiOutputRegressor(
            RandomForestRegressor(
                n_estimators=100,
                max_depth=10,
                random_state=42
            )
        )
        
        X = features[self.FEATURE_COLUMNS]
        y = features[['cpu_cores', 'memory_gb', 'runtime_minutes']]
        
        # Train with cross-validation
        cv_scores = cross_val_score(model, X, y, cv=5, scoring='neg_mean_squared_error')
        
        model.fit(X, y)
        
        # Calculate feature importance
        feature_importance = self._calculate_feature_importance(model, X.columns)
        
        return {
            'model': model,
            'cv_scores': cv_scores,
            'feature_importance': feature_importance,
            'training_metrics': self._calculate_training_metrics(model, X, y)
        }
```

### Rule-Based Estimation

```python
class RuleBasedEstimator:
    RESOURCE_RULES = {
        'postgres': {
            'base_cpu': 2,
            'base_memory_gb': 4,
            'cpu_per_gb': 0.1,
            'memory_per_gb': 0.3,
            'runtime_base_minutes': 5,
            'runtime_per_gb_minutes': 2,
            'connection_overhead_cpu': 0.5,
            'index_efficiency_factor': 0.8
        },
        'mysql': {
            'base_cpu': 2,
            'base_memory_gb': 4,
            'cpu_per_gb': 0.12,
            'memory_per_gb': 0.25,
            'runtime_base_minutes': 6,
            'runtime_per_gb_minutes': 2.2
        },
        's3': {
            'base_cpu': 1,
            'base_memory_gb': 2,
            'cpu_per_gb': 0.05,
            'memory_per_gb': 0.15,
            'runtime_base_minutes': 3,
            'runtime_per_gb_minutes': 1.5,
            'file_count_factor': 0.001,
            'compression_factor': {
                'none': 1.0,
                'gzip': 0.7,
                'snappy': 0.9,
                'lz4': 0.85
            }
        }
    }
    
    def estimate(self, job_config):
        source_type = job_config['source_type']
        rules = self.RESOURCE_RULES.get(source_type, self.RESOURCE_RULES['postgres'])
        
        # Base calculations
        estimated_data_gb = self._estimate_data_volume(job_config)
        
        cpu_cores = rules['base_cpu'] + (estimated_data_gb * rules['cpu_per_gb'])
        memory_gb = rules['base_memory_gb'] + (estimated_data_gb * rules['memory_per_gb'])
        runtime_minutes = rules['runtime_base_minutes'] + (estimated_data_gb * rules['runtime_per_gb_minutes'])
        
        # Apply source-specific adjustments
        if source_type in ['postgres', 'mysql']:
            cpu_cores += rules.get('connection_overhead_cpu', 0)
            if self._has_indexes(job_config):
                runtime_minutes *= rules.get('index_efficiency_factor', 1.0)
        
        elif source_type == 's3':
            file_count = self._estimate_file_count(job_config)
            cpu_cores += file_count * rules.get('file_count_factor', 0)
            
            compression = job_config.get('compression', 'none')
            compression_factor = rules['compression_factor'].get(compression, 1.0)
            runtime_minutes *= compression_factor
        
        # Apply transformation complexity multiplier
        complexity_multiplier = self._get_complexity_multiplier(job_config)
        cpu_cores *= complexity_multiplier
        memory_gb *= complexity_multiplier
        runtime_minutes *= complexity_multiplier
        
        return {
            'cpu_cores': max(1, int(cpu_cores)),
            'memory_gb': max(2, int(memory_gb)),
            'runtime_minutes': max(5, int(runtime_minutes)),
            'confidence': 0.7,
            'method': 'rule_based'
        }
```

### Similarity-Based Estimation

```python
class SimilarityEstimator:
    def __init__(self):
        self.similarity_threshold = 0.8
        self.max_similar_jobs = 10
    
    def estimate(self, job_config):
        """
        Estimate based on similar historical jobs
        """
        similar_jobs = self._find_similar_jobs(job_config)
        
        if len(similar_jobs) < 3:
            return None  # Not enough similar jobs
        
        # Weight similar jobs by similarity score
        weighted_estimates = []
        total_weight = 0
        
        for job, similarity_score in similar_jobs:
            weight = similarity_score ** 2  # Square to emphasize higher similarity
            weighted_estimates.append({
                'cpu_cores': job['actual_cpu'] * weight,
                'memory_gb': job['actual_memory'] * weight,
                'runtime_minutes': job['actual_runtime'] * weight
            })
            total_weight += weight
        
        # Calculate weighted average
        avg_cpu = sum(est['cpu_cores'] for est in weighted_estimates) / total_weight
        avg_memory = sum(est['memory_gb'] for est in weighted_estimates) / total_weight
        avg_runtime = sum(est['runtime_minutes'] for est in weighted_estimates) / total_weight
        
        # Calculate confidence based on similarity scores and variance
        confidence = self._calculate_confidence(similar_jobs)
        
        return {
            'cpu_cores': int(avg_cpu),
            'memory_gb': int(avg_memory),
            'runtime_minutes': int(avg_runtime),
            'confidence': confidence,
            'method': 'similarity_based',
            'similar_jobs_count': len(similar_jobs)
        }
    
    def _find_similar_jobs(self, job_config):
        """
        Find historically similar jobs using multiple similarity metrics
        """
        historical_jobs = self._get_historical_jobs(job_config['tenant_id'])
        similarities = []
        
        for historical_job in historical_jobs:
            similarity_score = self._calculate_similarity(job_config, historical_job)
            if similarity_score >= self.similarity_threshold:
                similarities.append((historical_job, similarity_score))
        
        # Sort by similarity and return top matches
        similarities.sort(key=lambda x: x[1], reverse=True)
        return similarities[:self.max_similar_jobs]
    
    def _calculate_similarity(self, job_config, historical_job):
        """
        Calculate multi-dimensional similarity score
        """
        # Source type similarity (exact match required)
        if job_config['source_type'] != historical_job['source_type']:
            return 0.0
        
        # Data volume similarity
        current_volume = self._estimate_data_volume(job_config)
        historical_volume = historical_job['data_volume_gb']
        volume_similarity = 1.0 - abs(current_volume - historical_volume) / max(current_volume, historical_volume)
        
        # Configuration similarity
        config_similarity = self._calculate_config_similarity(job_config, historical_job)
        
        # Transformation similarity
        transform_similarity = self._calculate_transformation_similarity(job_config, historical_job)
        
        # Weighted combination
        weights = {
            'volume': 0.4,
            'config': 0.3,
            'transformation': 0.3
        }
        
        total_similarity = (
            volume_similarity * weights['volume'] +
            config_similarity * weights['config'] +
            transform_similarity * weights['transformation']
        )
        
        return total_similarity
```

## Capacity Management System

### Time-Slot Based Scheduling

```python
class CapacityManager:
    def __init__(self):
        self.slot_duration_minutes = 15  # 15-minute time slots
        self.lookahead_hours = 168  # 1 week lookahead
        self.capacity_buffer = 0.1  # 10% buffer for safety
    
    def initialize_capacity_slots(self):
        """
        Pre-compute capacity slots for efficient scheduling
        """
        current_time = datetime.utcnow()
        end_time = current_time + timedelta(hours=self.lookahead_hours)
        
        slot_time = current_time.replace(minute=0, second=0, microsecond=0)
        
        while slot_time < end_time:
            for namespace in ['dedicated-cpu-ns', 'vcpu-hours-ns', 'draft-ingestion-ns']:
                total_capacity = self._get_namespace_capacity(namespace)
                
                slot = CapacitySlot(
                    namespace=namespace,
                    time_slot=slot_time,
                    duration_minutes=self.slot_duration_minutes,
                    total_cpu_capacity=total_capacity['cpu'],
                    total_memory_capacity=total_capacity['memory'],
                    allocated_cpu=0,
                    allocated_memory=0
                )
                
                self._save_capacity_slot(slot)
            
            slot_time += timedelta(minutes=self.slot_duration_minutes)
    
    def find_optimal_slot(self, job_requirements, preferred_time, sla_window_hours=24):
        """
        Find optimal capacity slot considering multiple factors
        """
        required_cpu = job_requirements['cpu_cores']
        required_memory = job_requirements['memory_gb']
        estimated_duration = job_requirements['estimated_runtime_minutes']
        
        # Calculate number of slots needed
        slots_needed = math.ceil(estimated_duration / self.slot_duration_minutes)
        
        # Search window
        search_start = preferred_time
        search_end = preferred_time + timedelta(hours=sla_window_hours)
        
        best_slot = None
        best_score = -1
        
        current_time = search_start
        while current_time <= search_end:
            for namespace in self._get_eligible_namespaces(job_requirements):
                slot_sequence = self._get_slot_sequence(namespace, current_time, slots_needed)
                
                if self._can_allocate_sequence(slot_sequence, required_cpu, required_memory):
                    score = self._calculate_slot_score(slot_sequence, preferred_time, job_requirements)
                    
                    if score > best_score:
                        best_score = score
                        best_slot = {
                            'namespace': namespace,
                            'start_slot': slot_sequence[0],
                            'slot_sequence': slot_sequence,
                            'score': score
                        }
            
            current_time += timedelta(minutes=self.slot_duration_minutes)
        
        return best_slot
    
    def _calculate_slot_score(self, slot_sequence, preferred_time, job_requirements):
        """
        Calculate score for slot allocation considering multiple factors
        """
        start_time = slot_sequence[0].time_slot
        
        # Time preference score (closer to preferred time is better)
        time_diff_hours = abs((start_time - preferred_time).total_seconds()) / 3600
        time_score = max(0, 1 - (time_diff_hours / 24))  # Normalize to 0-1
        
        # Resource utilization score (better utilization is preferred)
        total_capacity = sum(slot.total_cpu_capacity for slot in slot_sequence)
        total_allocated = sum(slot.allocated_cpu for slot in slot_sequence)
        utilization_score = (total_allocated + job_requirements['cpu_cores']) / total_capacity
        
        # Fragmentation score (prefer contiguous slots)
        fragmentation_score = 1.0 if len(slot_sequence) == 1 else 0.8
        
        # Priority score based on job priority
        priority_multiplier = {
            'low': 0.8,
            'medium': 1.0,
            'high': 1.2,
            'critical': 1.5
        }.get(job_requirements.get('priority', 'medium'), 1.0)
        
        # Weighted combination
        final_score = (
            time_score * 0.4 +
            utilization_score * 0.3 +
            fragmentation_score * 0.3
        ) * priority_multiplier
        
        return final_score
```

### Cross-Namespace Resource Sharing

```python
class CrossNamespaceScheduler:
    def __init__(self):
        self.idle_threshold_percentage = 20  # Consider namespace idle if < 20% utilized
        self.spillover_enabled = True
        self.spillover_cost_multiplier = 1.2  # 20% cost increase for spillover
    
    def schedule_with_spillover(self, job, tenant_resources):
        """
        Schedule job with intelligent spillover to other namespaces
        """
        primary_namespace = self._get_primary_namespace(tenant_resources)
        
        # Try primary namespace first
        primary_slot = self.capacity_manager.find_optimal_slot(
            job.resource_requirements,
            job.preferred_time,
            namespace=primary_namespace
        )
        
        if primary_slot and primary_slot['score'] > 0.7:  # Good slot found
            return self._schedule_job(job, primary_slot)
        
        # Check for spillover opportunities
        spillover_options = self._find_spillover_opportunities(job, tenant_resources)
        
        if spillover_options:
            best_spillover = max(spillover_options, key=lambda x: x['adjusted_score'])
            
            # Check if spillover is worth it
            if self._is_spillover_beneficial(primary_slot, best_spillover, job):
                return self._schedule_spillover_job(job, best_spillover, tenant_resources)
        
        # Fallback to draft namespace for testing
        return self._schedule_in_draft_namespace(job)
    
    def _find_spillover_opportunities(self, job, tenant_resources):
        """
        Find opportunities to use idle capacity in other namespaces
        """
        opportunities = []
        current_time = datetime.utcnow()
        
        for namespace in ['dedicated-cpu-ns', 'vcpu-hours-ns']:
            if namespace == self._get_primary_namespace(tenant_resources):
                continue
            
            # Check if namespace has idle capacity
            utilization = self._get_namespace_utilization(namespace, current_time)
            
            if utilization < self.idle_threshold_percentage:
                slot = self.capacity_manager.find_optimal_slot(
                    job.resource_requirements,
                    job.preferred_time,
                    namespace=namespace
                )
                
                if slot:
                    # Calculate adjusted score considering spillover cost
                    adjusted_score = slot['score'] * (1 / self.spillover_cost_multiplier)
                    
                    opportunities.append({
                        'namespace': namespace,
                        'slot': slot,
                        'original_score': slot['score'],
                        'adjusted_score': adjusted_score,
                        'idle_percentage': 100 - utilization,
                        'spillover_cost': self._calculate_spillover_cost(job, namespace)
                    })
        
        return opportunities
    
    def _is_spillover_beneficial(self, primary_slot, spillover_option, job):
        """
        Determine if spillover is beneficial considering cost and timing
        """
        if not primary_slot:
            return True  # No choice, spillover is only option
        
        # Compare adjusted scores
        primary_score = primary_slot['score']
        spillover_score = spillover_option['adjusted_score']
        
        # Consider time sensitivity
        time_diff = abs((spillover_option['slot']['start_slot'].time_slot - 
                        primary_slot['start_slot'].time_slot).total_seconds()) / 3600
        
        # If spillover is significantly better and time difference is acceptable
        if spillover_score > primary_score * 1.1 and time_diff < 2:
            return True
        
        # If primary slot is significantly delayed
        preferred_time = job.preferred_time
        primary_delay = (primary_slot['start_slot'].time_slot - preferred_time).total_seconds() / 3600
        spillover_delay = (spillover_option['slot']['start_slot'].time_slot - preferred_time).total_seconds() / 3600
        
        if primary_delay > 4 and spillover_delay < primary_delay * 0.5:
            return True
        
        return False
```

### Dynamic Capacity Adjustment

```python
class DynamicCapacityAdjuster:
    def __init__(self):
        self.adjustment_interval_minutes = 5
        self.scale_up_threshold = 0.8  # Scale up if utilization > 80%
        self.scale_down_threshold = 0.3  # Scale down if utilization < 30%
        self.min_capacity_buffer = 0.2  # Always maintain 20% buffer
    
    def monitor_and_adjust(self):
        """
        Continuously monitor and adjust namespace capacities
        """
        for namespace in ['dedicated-cpu-ns', 'vcpu-hours-ns']:
            current_metrics = self._get_namespace_metrics(namespace)
            
            adjustment_needed = self._analyze_capacity_needs(namespace, current_metrics)
            
            if adjustment_needed:
                self._apply_capacity_adjustment(namespace, adjustment_needed)
    
    def _analyze_capacity_needs(self, namespace, metrics):
        """
        Analyze if capacity adjustment is needed
        """
        current_utilization = metrics['cpu_utilization']
        memory_utilization = metrics['memory_utilization']
        queue_length = metrics['pending_jobs']
        
        # Predict future utilization based on scheduled jobs
        predicted_utilization = self._predict_utilization(namespace, lookahead_hours=2)
        
        # Scale up conditions
        if (current_utilization > self.scale_up_threshold or 
            predicted_utilization > self.scale_up_threshold or
            queue_length > 10):
            
            scale_factor = self._calculate_scale_up_factor(metrics, predicted_utilization)
            return {
                'action': 'scale_up',
                'factor': scale_factor,
                'reason': 'high_utilization_or_queue_length'
            }
        
        # Scale down conditions
        elif (current_utilization < self.scale_down_threshold and 
              predicted_utilization < self.scale_down_threshold and
              queue_length == 0):
            
            scale_factor = self._calculate_scale_down_factor(metrics, predicted_utilization)
            return {
                'action': 'scale_down',
                'factor': scale_factor,
                'reason': 'low_utilization'
            }
        
        return None
    
    def _apply_capacity_adjustment(self, namespace, adjustment):
        """
        Apply capacity adjustment to namespace
        """
        current_capacity = self._get_namespace_capacity(namespace)
        
        if adjustment['action'] == 'scale_up':
            new_cpu_capacity = int(current_capacity['cpu'] * adjustment['factor'])
            new_memory_capacity = int(current_capacity['memory'] * adjustment['factor'])
        else:  # scale_down
            new_cpu_capacity = max(
                int(current_capacity['cpu'] * adjustment['factor']),
                int(current_capacity['cpu'] * (1 + self.min_capacity_buffer))
            )
            new_memory_capacity = max(
                int(current_capacity['memory'] * adjustment['factor']),
                int(current_capacity['memory'] * (1 + self.min_capacity_buffer))
            )
        
        # Update Kubernetes resource quotas
        self._update_namespace_quota(namespace, new_cpu_capacity, new_memory_capacity)
        
        # Update capacity slots
        self._update_future_capacity_slots(namespace, new_cpu_capacity, new_memory_capacity)
        
        # Log adjustment
        self._log_capacity_adjustment(namespace, adjustment, current_capacity, {
            'cpu': new_cpu_capacity,
            'memory': new_memory_capacity
        })
```

This deep dive document provides comprehensive technical details for implementing the resource estimation and capacity management components of the Spark Ingestion Service.
