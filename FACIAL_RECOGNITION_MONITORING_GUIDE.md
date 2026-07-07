# Facial Recognition - Production Monitoring & Diagnostics Guide

## Overview

This guide provides comprehensive monitoring strategies and diagnostic tools for the facial recognition system in production. It covers logging, metrics, debugging techniques, and troubleshooting procedures.

## Logging Architecture

### 1. **Structured Logging Levels**

```dart
// UserIdentityService logs
Logger.info('UserIdentityService: Using CustomerController identity - ${user.name} (ID: ${user.uid})');
Logger.warning('UserIdentityService: CustomerController.logeInCustomer is null, checking Firebase Auth...');
Logger.error('UserIdentityService: No user identity available - user not logged in');
Logger.debug('===== User Identity Details ($context) =====');

// FaceRecognitionService logs  
Logger.info('Enrollment saved to Firestore: FaceEnrollments/$docId (attempt $attempts)');
Logger.success('✅ Enrollment verification successful');
Logger.error('❌ Enrollment verification failed - document not found or invalid');
Logger.debug('Checking enrollment at: FaceEnrollments/$docId');
```

### 2. **Log Categories**

- **IDENTITY**: User identity resolution events
- **ENROLLMENT**: Face enrollment operations
- **SCANNER**: Face scanning and matching
- **SESSION**: Authentication and session management
- **PERFORMANCE**: Timing and performance metrics

## Real-time Monitoring Dashboard

### Key Metrics to Track

```yaml
facial_recognition_metrics:
  identity_resolution:
    total_resolutions: counter
    by_source:
      customer_controller: counter
      firebase_auth: counter
      guest: counter
    failures: counter
    
  enrollment:
    attempts: counter
    successes: counter
    failures: counter
    verification_failures: counter
    retry_count: histogram
    duration_ms: histogram
    
  scanning:
    sessions: counter
    successful_matches: counter
    failed_matches: counter
    no_enrollment_found: counter
    match_confidence: histogram
    time_to_match_ms: histogram
    
  errors:
    by_type:
      identity_resolution: counter
      enrollment_save: counter
      scanner_init: counter
      face_detection: counter
```

### Sample Grafana Dashboard Configuration

```json
{
  "dashboard": {
    "title": "Facial Recognition Monitoring",
    "panels": [
      {
        "title": "Identity Resolution Sources",
        "type": "pie",
        "targets": [
          {
            "expr": "sum(identity_resolution_by_source) by (source)"
          }
        ]
      },
      {
        "title": "Enrollment Success Rate",
        "type": "gauge",
        "targets": [
          {
            "expr": "rate(enrollment_successes[5m]) / rate(enrollment_attempts[5m]) * 100"
          }
        ]
      },
      {
        "title": "Recognition Performance",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, time_to_match_ms)"
          }
        ]
      }
    ]
  }
}
```

 

### 3. **Network Request Inspector**

```dart
class FirestoreRequestMonitor {
  static final List<RequestLog> _requests = [];
  
  static Future<T> monitor<T>(
    String operation,
    Future<T> Function() request,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await request();
      stopwatch.stop();
      
      _requests.add(RequestLog(
        operation: operation,
        duration: stopwatch.elapsedMilliseconds,
        success: true,
        timestamp: DateTime.now(),
      ));
      
      return result;
    } catch (e) {
      stopwatch.stop();
      
      _requests.add(RequestLog(
        operation: operation,
        duration: stopwatch.elapsedMilliseconds,
        success: false,
        error: e.toString(),
        timestamp: DateTime.now(),
      ));
      
      rethrow;
    }
  }
}
```

## Production Debugging Procedures

### Issue 1: User Reports "Face Not Recognized"

**Step 1: Check Identity Consistency**
```bash
# Query logs for user
grep "User ID: USER_ID_HERE" app.log | grep -E "(Enrollment|Scanner)"
```

**Step 2: Verify Enrollment**
```javascript
// Firebase Console query
db.collection('FaceEnrollments')
  .where('userId', '==', 'USER_ID_HERE')
  .where('eventId', '==', 'EVENT_ID_HERE')
  .get();
```

**Step 3: Check Recognition Attempts**
```bash
# Find match attempts
grep "Checking enrollment for.*USER_ID_HERE" app.log
grep "Match result.*USER_ID_HERE" app.log
```

### Issue 2: High Enrollment Failure Rate

**Diagnostic Query:**
```sql
SELECT 
  DATE_TRUNC('hour', timestamp) as hour,
  COUNT(*) as total_attempts,
  SUM(CASE WHEN success THEN 1 ELSE 0 END) as successes,
  AVG(retry_count) as avg_retries
FROM enrollment_logs
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY 1
ORDER BY 1 DESC;
```

**Common Causes:**
- Firestore permission issues
- Network timeouts
- Firebase quota limits

### Issue 3: Slow Recognition Performance

**Performance Analysis:**
```javascript
// Add timing logs
const timings = {
  identityResolution: 0,
  enrollmentCheck: 0,
  faceDetection: 0,
  featureExtraction: 0,
  matching: 0,
  total: 0
};

// Log to monitoring service
analytics.track('face_recognition_performance', timings);
```

## Alert Configuration

### Critical Alerts

```yaml
alerts:
  - name: "High Enrollment Failure Rate"
    condition: "rate(enrollment_failures[5m]) > 0.1"
    severity: "critical"
    notification: ["pagerduty", "slack"]
    
  - name: "Identity Resolution Failures"
    condition: "rate(identity_resolution_failures[5m]) > 0.05"
    severity: "warning"
    notification: ["slack"]
    
  - name: "Slow Recognition Performance"
    condition: "histogram_quantile(0.95, time_to_match_ms) > 5000"
    severity: "warning"
    notification: ["email"]
```

### Alert Response Playbook

**High Enrollment Failure Rate:**
1. Check Firestore status page
2. Verify Firebase quotas
3. Check network connectivity
4. Review recent code deployments
5. Enable verbose logging for affected users

**Identity Resolution Failures:**
1. Check AuthService initialization
2. Verify Firebase Auth status
3. Check for CustomerController issues
4. Review session management logs

## User Support Tools

### 1. **Self-Service Diagnostic Tool**

Add to help/settings screen:

```dart
class FacialRecognitionDiagnostic extends StatelessWidget {
  Future<DiagnosticResult> runDiagnostic() async {
    final results = DiagnosticResult();
    
    // Check user identity
    final identity = await UserIdentityService.getCurrentUserIdentity();
    results.addCheck('User Identity', identity != null, 
      details: identity?.toString());
    
    // Check enrollment
    if (identity != null) {
      final enrolled = await faceService.isUserEnrolled(
        userId: identity.userId,
        eventId: currentEvent.id,
      );
      results.addCheck('Face Enrolled', enrolled);
    }
    
    // Check camera permissions
    final cameraPermission = await Permission.camera.status;
    results.addCheck('Camera Permission', cameraPermission.isGranted);
    
    return results;
  }
}
```

### 2. **Support Dashboard**

For customer support teams:

```typescript
interface UserFacialRecognitionInfo {
  userId: string;
  enrollments: Array<{
    eventId: string;
    eventName: string;
    enrolledAt: Date;
    lastUsed?: Date;
    successfulScans: number;
    failedScans: number;
  }>;
  recentIssues: Array<{
    timestamp: Date;
    type: 'enrollment' | 'recognition' | 'identity';
    error: string;
    resolved: boolean;
  }>;
}
```

## Continuous Improvement

### A/B Testing Framework

```dart
class FacialRecognitionExperiments {
  static bool useEnhancedMatching() {
    return RemoteConfig.getBool('face_enhanced_matching');
  }
  
  static double getMatchingThreshold() {
    return RemoteConfig.getDouble('face_matching_threshold') ?? 0.7;
  }
  
  static int getRequiredSamples() {
    return RemoteConfig.getInt('face_required_samples') ?? 5;
  }
}
```

### Performance Optimization Checklist

- [ ] Monitor p95 latency for all operations
- [ ] Track memory usage during face processing
- [ ] Measure battery impact of continuous scanning
- [ ] Analyze network bandwidth usage
- [ ] Profile ML model inference time

## Data Privacy & Compliance

### Audit Logging

```dart
class BiometricAuditLogger {
  static void logEnrollment(String userId, String eventId) {
    AuditLog.record(
      action: 'BIOMETRIC_ENROLLMENT',
      userId: userId,
      metadata: {
        'eventId': eventId,
        'timestamp': DateTime.now().toIso8601String(),
        'dataType': 'facial_features',
        'retention': '90_days',
      },
    );
  }
  
  static void logAccess(String userId, String purpose) {
    AuditLog.record(
      action: 'BIOMETRIC_ACCESS',
      userId: userId,
      metadata: {
        'purpose': purpose,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}
```

### Data Retention Policy

```yaml
biometric_data_retention:
  facial_features:
    retention_period: "90 days"
    deletion_policy: "automatic"
    user_request_deletion: "immediate"
  
  audit_logs:
    retention_period: "1 year"
    deletion_policy: "automatic"
    
  attendance_records:
    retention_period: "indefinite"
    anonymization: "after 1 year"
```

## Emergency Procedures

### Rollback Plan

```bash
# If critical issues arise:

# 1. Feature flag disable
firebase remoteconfig:set face_recognition_enabled false

# 2. Revert to previous version
git revert HEAD
flutter build appbundle --release

# 3. Clear problematic data
firebase firestore:delete FaceEnrollments --where eventId == AFFECTED_EVENT

# 4. Notify users
firebase messaging:send --topic=all --data='{"alert":"Facial recognition temporarily disabled"}'
```

### Incident Response Template

```markdown
## Incident Report: Facial Recognition Issue

**Date:** [DATE]
**Severity:** [Critical/High/Medium/Low]
**Duration:** [START] - [END]

### Impact
- Affected Users: [COUNT]
- Failed Enrollments: [COUNT]
- Failed Recognitions: [COUNT]

### Root Cause
[Description of root cause]

### Resolution
[Steps taken to resolve]

### Prevention
[Measures to prevent recurrence]

### Metrics
- Time to Detection: [MINUTES]
- Time to Resolution: [MINUTES]
- Customer Complaints: [COUNT]
```

## Summary

Effective monitoring and diagnostics require:
1. Comprehensive structured logging
2. Real-time metrics collection
3. Proactive alerting
4. User-friendly debugging tools
5. Clear incident response procedures
6. Continuous performance optimization
7. Strong privacy compliance measures

Regular review of these systems ensures the facial recognition feature remains reliable, performant, and user-friendly.
