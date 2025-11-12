# SLA Management and Job Promotion System

## Overview

The SLA Management and Job Promotion System ensures that ingestion jobs meet performance requirements and are promoted from draft to production namespaces based on validated performance metrics.

## Draft Namespace Testing Framework

### Draft Execution Pipeline

```python
class DraftExecutionManager:
    def __init__(self):
        self.draft_namespace = 'draft-ingestion-ns'
        self.test_execution_days = 7  # Test for 7 days by default
        self.min_successful_runs = 3  # Minimum successful runs for promotion
        self.performance_threshold = 1.2  # Within 20% of estimate
    
    def schedule_draft_execution(self, job):
        """
        Schedule job in draft namespace for testing
        """
        # Create draft execution plan
        draft_plan = self._create_draft_execution_plan(job)
        
        # Allocate resources in draft namespace
        draft_resources = self._allocate_draft_resources(job, draft_plan)
        
        # Schedule test executions
        test_executions = self._schedule_test_executions(job, draft_plan)
        
        # Set up monitoring and evaluation
        self._setup_draft_monitoring(job, test_executions)
        
        return {
            'draft_plan_id': draft_plan.id,
            'test_executions': test_executions,
            'evaluation_schedule': draft_plan.evaluation_dates,
            'promotion_criteria': self._get_promotion_criteria(job)
        }
    
    def _create_draft_execution_plan(self, job):
        """
        Create comprehensive testing plan for draft execution
        """
        # Determine test frequency based on job schedule
        original_schedule = job.schedule_config['cron']
        test_frequency = self._calculate_test_frequency(original_schedule)
        
        # Calculate resource allocation for testing
        estimated_resources = job.resource_requirements
        test_resources = self._calculate_test_resources(estimated_resources)
        
        # Create evaluation milestones
        evaluation_dates = self._generate_evaluation_dates(test_frequency)
        
        return DraftExecutionPlan(
            job_id=job.job_id,
            test_frequency=test_frequency,
            test_resources=test_resources,
            evaluation_dates=evaluation_dates,
            success_criteria=self._define_success_criteria(job),
            created_at=datetime.utcnow()
        )
    
    def _calculate_test_frequency(self, original_cron):
        """
        Calculate appropriate test frequency for draft execution
        """
        # Parse original cron to understand frequency
        cron_parts = original_cron.split()
        
        if cron_parts[1] == '*':  # Hourly job
            return 'every_4_hours'  # Test every 4 hours
        elif cron_parts[2] == '*':  # Daily job
            return 'twice_daily'    # Test twice daily
        elif cron_parts[4] == '*':  # Weekly job
            return 'daily'          # Test daily
        else:  # Monthly or less frequent
            return 'every_2_days'   # Test every 2 days
        
    def _calculate_test_resources(self, estimated_resources):
        """
        Calculate resource allocation for testing (potentially reduced)
        """
        # Use slightly higher resources for testing to account for overhead
        return {
            'cpu_cores': max(1, int(estimated_resources['cpu_cores'] * 1.1)),
            'memory_gb': max(2, int(estimated_resources['memory_gb'] * 1.1)),
            'estimated_runtime_minutes': int(estimated_resources['estimated_runtime_minutes'] * 1.2)
        }
```

### Performance Evaluation Engine

```python
class PerformanceEvaluator:
    def __init__(self):
        self.evaluation_metrics = [
            'runtime_performance',
            'resource_utilization',
            'data_quality',
            'error_rate',
            'sla_compliance'
        ]
    
    def evaluate_draft_execution(self, execution):
        """
        Comprehensive evaluation of draft execution performance
        """
        evaluation_results = {}
        
        for metric in self.evaluation_metrics:
            evaluator_method = getattr(self, f'_evaluate_{metric}')
            evaluation_results[metric] = evaluator_method(execution)
        
        # Calculate overall score
        overall_score = self._calculate_overall_score(evaluation_results)
        
        # Generate recommendations
        recommendations = self._generate_recommendations(evaluation_results, execution)
        
        return PerformanceEvaluation(
            execution_id=execution.execution_id,
            job_id=execution.job_id,
            evaluation_results=evaluation_results,
            overall_score=overall_score,
            recommendations=recommendations,
            promotion_eligible=overall_score >= 0.8,
            evaluated_at=datetime.utcnow()
        )
    
    def _evaluate_runtime_performance(self, execution):
        """
        Evaluate runtime performance against estimates
        """
        actual_runtime = execution.actual_runtime_minutes
        estimated_runtime = execution.job.resource_requirements['estimated_runtime_minutes']
        
        performance_ratio = actual_runtime / estimated_runtime
        
        if performance_ratio <= 1.0:
            score = 1.0  # Better than expected
            status = 'excellent'
        elif performance_ratio <= 1.2:
            score = 0.9  # Within 20% - acceptable
            status = 'good'
        elif performance_ratio <= 1.5:
            score = 0.7  # Within 50% - needs attention
            status = 'acceptable'
        else:
            score = 0.4  # More than 50% over - poor
            status = 'poor'
        
        return {
            'score': score,
            'status': status,
            'actual_runtime_minutes': actual_runtime,
            'estimated_runtime_minutes': estimated_runtime,
            'performance_ratio': performance_ratio,
            'variance_percentage': (performance_ratio - 1.0) * 100
        }
    
    def _evaluate_resource_utilization(self, execution):
        """
        Evaluate how efficiently resources were used
        """
        allocated_cpu = execution.allocated_resources['cpu_cores']
        allocated_memory = execution.allocated_resources['memory_gb']
        
        actual_cpu_usage = execution.resource_usage['avg_cpu_utilization']
        actual_memory_usage = execution.resource_usage['peak_memory_usage_gb']
        
        cpu_efficiency = actual_cpu_usage / allocated_cpu
        memory_efficiency = actual_memory_usage / allocated_memory
        
        # Ideal efficiency is 70-90%
        cpu_score = self._calculate_efficiency_score(cpu_efficiency)
        memory_score = self._calculate_efficiency_score(memory_efficiency)
        
        overall_efficiency = (cpu_score + memory_score) / 2
        
        return {
            'score': overall_efficiency,
            'cpu_efficiency': cpu_efficiency,
            'memory_efficiency': memory_efficiency,
            'cpu_score': cpu_score,
            'memory_score': memory_score,
            'recommendations': self._get_resource_recommendations(cpu_efficiency, memory_efficiency)
        }
    
    def _evaluate_data_quality(self, execution):
        """
        Evaluate data quality metrics
        """
        quality_metrics = execution.data_quality_results
        
        if not quality_metrics:
            return {'score': 0.5, 'status': 'no_quality_checks', 'message': 'No data quality checks configured'}
        
        total_checks = len(quality_metrics['checks'])
        passed_checks = len([check for check in quality_metrics['checks'] if check['status'] == 'passed'])
        failed_checks = len([check for check in quality_metrics['checks'] if check['status'] == 'failed'])
        warning_checks = len([check for check in quality_metrics['checks'] if check['status'] == 'warning'])
        
        # Calculate score based on check results
        if failed_checks == 0:
            if warning_checks == 0:
                score = 1.0  # Perfect
                status = 'excellent'
            else:
                score = 0.8  # Some warnings
                status = 'good'
        else:
            if failed_checks / total_checks <= 0.1:
                score = 0.6  # Few failures
                status = 'acceptable'
            else:
                score = 0.3  # Many failures
                status = 'poor'
        
        return {
            'score': score,
            'status': status,
            'total_checks': total_checks,
            'passed_checks': passed_checks,
            'failed_checks': failed_checks,
            'warning_checks': warning_checks,
            'pass_rate': passed_checks / total_checks if total_checks > 0 else 0
        }
    
    def _calculate_efficiency_score(self, efficiency):
        """
        Calculate efficiency score with ideal range of 70-90%
        """
        if 0.7 <= efficiency <= 0.9:
            return 1.0  # Ideal efficiency
        elif 0.5 <= efficiency < 0.7:
            return 0.8  # Under-utilized but acceptable
        elif 0.9 < efficiency <= 1.0:
            return 0.9  # Fully utilized
        elif efficiency > 1.0:
            return 0.6  # Over-allocated (shouldn't happen but handle gracefully)
        else:
            return 0.4  # Severely under-utilized
```

### SLA Compliance Tracking

```python
class SLAComplianceTracker:
    def __init__(self):
        self.sla_metrics = [
            'max_runtime',
            'success_rate',
            'data_freshness',
            'availability',
            'error_recovery_time'
        ]
    
    def track_sla_compliance(self, job, execution_history):
        """
        Track SLA compliance across multiple executions
        """
        sla_requirements = job.sla_requirements
        compliance_results = {}
        
        for metric in self.sla_metrics:
            if metric in sla_requirements:
                compliance_results[metric] = self._check_sla_metric(
                    metric, 
                    sla_requirements[metric], 
                    execution_history
                )
        
        # Calculate overall SLA compliance
        overall_compliance = self._calculate_overall_compliance(compliance_results)
        
        # Generate SLA report
        sla_report = self._generate_sla_report(job, compliance_results, overall_compliance)
        
        return sla_report
    
    def _check_sla_metric(self, metric, sla_requirement, execution_history):
        """
        Check specific SLA metric compliance
        """
        if metric == 'max_runtime':
            return self._check_runtime_sla(sla_requirement, execution_history)
        elif metric == 'success_rate':
            return self._check_success_rate_sla(sla_requirement, execution_history)
        elif metric == 'data_freshness':
            return self._check_freshness_sla(sla_requirement, execution_history)
        elif metric == 'availability':
            return self._check_availability_sla(sla_requirement, execution_history)
        elif metric == 'error_recovery_time':
            return self._check_recovery_time_sla(sla_requirement, execution_history)
    
    def _check_runtime_sla(self, max_runtime_minutes, execution_history):
        """
        Check if executions meet runtime SLA
        """
        recent_executions = execution_history[-10:]  # Last 10 executions
        
        compliant_executions = [
            exec for exec in recent_executions 
            if exec.actual_runtime_minutes <= max_runtime_minutes
        ]
        
        compliance_rate = len(compliant_executions) / len(recent_executions) if recent_executions else 0
        
        avg_runtime = sum(exec.actual_runtime_minutes for exec in recent_executions) / len(recent_executions)
        
        return {
            'compliance_rate': compliance_rate,
            'avg_runtime_minutes': avg_runtime,
            'max_runtime_minutes': max_runtime_minutes,
            'violations': len(recent_executions) - len(compliant_executions),
            'status': 'compliant' if compliance_rate >= 0.9 else 'violation'
        }
    
    def _check_success_rate_sla(self, required_success_rate, execution_history):
        """
        Check if executions meet success rate SLA
        """
        recent_executions = execution_history[-20:]  # Last 20 executions
        
        successful_executions = [
            exec for exec in recent_executions 
            if exec.status == 'completed'
        ]
        
        actual_success_rate = len(successful_executions) / len(recent_executions) if recent_executions else 0
        
        return {
            'actual_success_rate': actual_success_rate,
            'required_success_rate': required_success_rate,
            'total_executions': len(recent_executions),
            'successful_executions': len(successful_executions),
            'status': 'compliant' if actual_success_rate >= required_success_rate else 'violation'
        }
```

## Job Promotion System

### Promotion Decision Engine

```python
class PromotionDecisionEngine:
    def __init__(self):
        self.promotion_criteria = {
            'min_successful_runs': 3,
            'min_evaluation_period_days': 3,
            'min_overall_score': 0.8,
            'max_performance_variance': 0.3,
            'min_sla_compliance': 0.9
        }
    
    def evaluate_promotion_eligibility(self, job, draft_executions):
        """
        Evaluate if job is eligible for promotion to production
        """
        # Collect all evaluation data
        evaluation_data = self._collect_evaluation_data(job, draft_executions)
        
        # Run promotion criteria checks
        criteria_results = self._check_promotion_criteria(evaluation_data)
        
        # Make promotion decision
        promotion_decision = self._make_promotion_decision(criteria_results, evaluation_data)
        
        return PromotionEvaluation(
            job_id=job.job_id,
            evaluation_data=evaluation_data,
            criteria_results=criteria_results,
            promotion_decision=promotion_decision,
            evaluated_at=datetime.utcnow()
        )
    
    def _collect_evaluation_data(self, job, draft_executions):
        """
        Collect comprehensive evaluation data
        """
        successful_executions = [exec for exec in draft_executions if exec.status == 'completed']
        failed_executions = [exec for exec in draft_executions if exec.status == 'failed']
        
        if not successful_executions:
            return {'error': 'no_successful_executions'}
        
        # Performance metrics
        runtimes = [exec.actual_runtime_minutes for exec in successful_executions]
        avg_runtime = sum(runtimes) / len(runtimes)
        runtime_variance = self._calculate_variance(runtimes, avg_runtime)
        
        # Resource utilization
        cpu_utilizations = [exec.resource_usage['avg_cpu_utilization'] for exec in successful_executions]
        memory_utilizations = [exec.resource_usage['peak_memory_usage_gb'] for exec in successful_executions]
        
        # SLA compliance
        sla_compliance = self._calculate_sla_compliance(job, draft_executions)
        
        # Data quality
        data_quality_scores = [exec.data_quality_score for exec in successful_executions if exec.data_quality_score]
        avg_data_quality = sum(data_quality_scores) / len(data_quality_scores) if data_quality_scores else 0.5
        
        return {
            'total_executions': len(draft_executions),
            'successful_executions': len(successful_executions),
            'failed_executions': len(failed_executions),
            'success_rate': len(successful_executions) / len(draft_executions),
            'avg_runtime_minutes': avg_runtime,
            'runtime_variance': runtime_variance,
            'avg_cpu_utilization': sum(cpu_utilizations) / len(cpu_utilizations),
            'avg_memory_utilization': sum(memory_utilizations) / len(memory_utilizations),
            'sla_compliance': sla_compliance,
            'avg_data_quality_score': avg_data_quality,
            'evaluation_period_days': (draft_executions[-1].created_at - draft_executions[0].created_at).days
        }
    
    def _check_promotion_criteria(self, evaluation_data):
        """
        Check each promotion criterion
        """
        if 'error' in evaluation_data:
            return {'overall_status': 'failed', 'error': evaluation_data['error']}
        
        criteria_results = {}
        
        # Minimum successful runs
        criteria_results['min_successful_runs'] = {
            'required': self.promotion_criteria['min_successful_runs'],
            'actual': evaluation_data['successful_executions'],
            'passed': evaluation_data['successful_executions'] >= self.promotion_criteria['min_successful_runs']
        }
        
        # Minimum evaluation period
        criteria_results['min_evaluation_period'] = {
            'required_days': self.promotion_criteria['min_evaluation_period_days'],
            'actual_days': evaluation_data['evaluation_period_days'],
            'passed': evaluation_data['evaluation_period_days'] >= self.promotion_criteria['min_evaluation_period_days']
        }
        
        # Performance variance
        criteria_results['performance_variance'] = {
            'max_allowed': self.promotion_criteria['max_performance_variance'],
            'actual': evaluation_data['runtime_variance'],
            'passed': evaluation_data['runtime_variance'] <= self.promotion_criteria['max_performance_variance']
        }
        
        # SLA compliance
        criteria_results['sla_compliance'] = {
            'min_required': self.promotion_criteria['min_sla_compliance'],
            'actual': evaluation_data['sla_compliance'],
            'passed': evaluation_data['sla_compliance'] >= self.promotion_criteria['min_sla_compliance']
        }
        
        # Overall score (composite of all metrics)
        overall_score = self._calculate_composite_score(evaluation_data)
        criteria_results['overall_score'] = {
            'min_required': self.promotion_criteria['min_overall_score'],
            'actual': overall_score,
            'passed': overall_score >= self.promotion_criteria['min_overall_score']
        }
        
        # Determine overall status
        all_passed = all(result['passed'] for result in criteria_results.values())
        criteria_results['overall_status'] = 'passed' if all_passed else 'failed'
        
        return criteria_results
    
    def _make_promotion_decision(self, criteria_results, evaluation_data):
        """
        Make final promotion decision with recommendations
        """
        if criteria_results['overall_status'] == 'passed':
            # Determine target namespace
            target_namespace = self._determine_target_namespace(evaluation_data)
            
            # Calculate recommended resource adjustments
            resource_adjustments = self._calculate_resource_adjustments(evaluation_data)
            
            return {
                'decision': 'promote',
                'target_namespace': target_namespace,
                'resource_adjustments': resource_adjustments,
                'confidence': self._calculate_promotion_confidence(criteria_results),
                'message': 'Job meets all promotion criteria and is ready for production'
            }
        else:
            # Identify specific issues and provide recommendations
            failed_criteria = [
                criterion for criterion, result in criteria_results.items() 
                if isinstance(result, dict) and not result.get('passed', True)
            ]
            
            recommendations = self._generate_improvement_recommendations(failed_criteria, evaluation_data)
            
            return {
                'decision': 'reject',
                'failed_criteria': failed_criteria,
                'recommendations': recommendations,
                'message': f'Job failed {len(failed_criteria)} promotion criteria. See recommendations for improvement.'
            }
```

### Automated Promotion Workflow

```python
class PromotionWorkflowManager:
    def __init__(self):
        self.promotion_queue = PromotionQueue()
        self.notification_service = NotificationService()
    
    def execute_promotion_workflow(self, promotion_evaluation):
        """
        Execute the complete promotion workflow
        """
        job_id = promotion_evaluation.job_id
        decision = promotion_evaluation.promotion_decision
        
        if decision['decision'] == 'promote':
            return self._execute_promotion(job_id, decision)
        else:
            return self._handle_promotion_rejection(job_id, decision)
    
    def _execute_promotion(self, job_id, promotion_decision):
        """
        Execute job promotion to production namespace
        """
        job = self._get_job(job_id)
        
        try:
            # Step 1: Apply resource adjustments
            if promotion_decision.get('resource_adjustments'):
                self._apply_resource_adjustments(job, promotion_decision['resource_adjustments'])
            
            # Step 2: Update job configuration
            job.namespace = promotion_decision['target_namespace']
            job.status = 'active'
            job.promoted_at = datetime.utcnow()
            
            # Step 3: Schedule in production namespace
            production_schedule = self._schedule_in_production(job, promotion_decision['target_namespace'])
            
            # Step 4: Clean up draft resources
            self._cleanup_draft_resources(job_id)
            
            # Step 5: Set up production monitoring
            self._setup_production_monitoring(job)
            
            # Step 6: Send success notification
            self._send_promotion_notification(job, 'success', promotion_decision)
            
            return {
                'status': 'promoted',
                'job_id': job_id,
                'target_namespace': promotion_decision['target_namespace'],
                'production_schedule': production_schedule,
                'message': 'Job successfully promoted to production'
            }
            
        except Exception as e:
            # Handle promotion failure
            self._handle_promotion_failure(job_id, str(e))
            raise PromotionException(f"Failed to promote job {job_id}: {str(e)}")
    
    def _handle_promotion_rejection(self, job_id, rejection_decision):
        """
        Handle job promotion rejection
        """
        job = self._get_job(job_id)
        
        # Update job status
        job.status = 'promotion_rejected'
        job.promotion_feedback = rejection_decision
        
        # Send detailed feedback to tenant
        feedback_report = self._generate_feedback_report(job, rejection_decision)
        self._send_promotion_feedback(job, feedback_report)
        
        # Optionally extend draft testing period
        if self._should_extend_draft_period(rejection_decision):
            self._extend_draft_testing(job_id)
        
        return {
            'status': 'rejected',
            'job_id': job_id,
            'failed_criteria': rejection_decision['failed_criteria'],
            'recommendations': rejection_decision['recommendations'],
            'feedback_report': feedback_report
        }
    
    def _generate_feedback_report(self, job, rejection_decision):
        """
        Generate detailed feedback report for tenant
        """
        report = {
            'job_name': job.job_name,
            'evaluation_summary': {
                'status': 'promotion_rejected',
                'failed_criteria': rejection_decision['failed_criteria'],
                'evaluation_date': datetime.utcnow().isoformat()
            },
            'detailed_recommendations': [],
            'next_steps': []
        }
        
        # Generate specific recommendations for each failed criterion
        for criterion in rejection_decision['failed_criteria']:
            if criterion == 'min_successful_runs':
                report['detailed_recommendations'].append({
                    'issue': 'Insufficient successful test runs',
                    'recommendation': 'Allow more time for draft testing to accumulate successful runs',
                    'action': 'Wait for additional test executions'
                })
            elif criterion == 'performance_variance':
                report['detailed_recommendations'].append({
                    'issue': 'High performance variance between runs',
                    'recommendation': 'Optimize job configuration or increase resource allocation',
                    'action': 'Review resource requirements and data source performance'
                })
            elif criterion == 'sla_compliance':
                report['detailed_recommendations'].append({
                    'issue': 'SLA compliance below threshold',
                    'recommendation': 'Adjust SLA requirements or improve job performance',
                    'action': 'Either relax SLA constraints or optimize job execution'
                })
        
        # Generate next steps
        report['next_steps'] = [
            'Review and implement the recommendations above',
            'Continue draft testing with improved configuration',
            'Monitor job performance in draft namespace',
            'Request re-evaluation after improvements are made'
        ]
        
        return report
```

This SLA management and job promotion system ensures that only well-performing, reliable jobs are promoted to production namespaces, maintaining high service quality while providing clear feedback for improvement when jobs don't meet promotion criteria.
