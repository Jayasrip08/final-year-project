import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Comprehensive logging service for debugging and monitoring
class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Log levels
  // ignore: constant_identifier_names
  static const String INFO = 'INFO';
  // ignore: constant_identifier_names
  static const String WARNING = 'WARNING';
  // ignore: constant_identifier_names
  static const String ERROR = 'ERROR';
  // ignore: constant_identifier_names
  static const String DEBUG = 'DEBUG';

  /// Log an event to Firestore
  Future<void> log({
    required String level,
    required String message,
    required String category,
    Map<String, dynamic>? metadata,
    String? userId,
    String? stackTrace,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      
      await _firestore.collection('logs').add({
        'level': level,
        'message': message,
        'category': category,
        'userId': userId ?? user?.uid,
        'userEmail': user?.email,
        'timestamp': FieldValue.serverTimestamp(),
        'metadata': metadata ?? {},
        'stackTrace': stackTrace,
        'platform': 'flutter',
      });

      // Also print to console in debug mode
      print('[$level] [$category] $message');
      if (metadata != null) {
        print('Metadata: $metadata');
      }
    } catch (e) {
      // Fallback to console if Firestore fails
      print('Failed to log to Firestore: $e');
      print('[$level] [$category] $message');
    }
  }

  /// Log info message
  Future<void> info(String message, {String category = 'General', Map<String, dynamic>? metadata}) async {
    await log(
      level: INFO,
      message: message,
      category: category,
      metadata: metadata,
    );
  }

  /// Log warning message
  Future<void> warning(String message, {String category = 'General', Map<String, dynamic>? metadata}) async {
    await log(
      level: WARNING,
      message: message,
      category: category,
      metadata: metadata,
    );
  }

  /// Log error message
  Future<void> error(
    String message, {
    String category = 'General',
    Map<String, dynamic>? metadata,
    dynamic error,
    StackTrace? stackTrace,
  }) async {
    await log(
      level: ERROR,
      message: message,
      category: category,
      metadata: {
        ...?metadata,
        if (error != null) 'error': error.toString(),
      },
      stackTrace: stackTrace?.toString(),
    );
  }

  /// Log debug message
  Future<void> debug(String message, {String category = 'General', Map<String, dynamic>? metadata}) async {
    await log(
      level: DEBUG,
      message: message,
      category: category,
      metadata: metadata,
    );
  }

  /// Log user action
  Future<void> logUserAction(String action, {Map<String, dynamic>? details}) async {
    await info(
      'User action: $action',
      category: 'UserAction',
      metadata: details,
    );
  }

  /// Log payment event
  Future<void> logPayment({
    required String action,
    required String studentId,
    String? transactionId,
    double? amount,
    String? status,
  }) async {
    await info(
      'Payment $action',
      category: 'Payment',
      metadata: {
        'studentId': studentId,
        'transactionId': transactionId,
        'amount': amount,
        'status': status,
      },
    );
  }

  /// Log authentication event
  Future<void> logAuth(String action, {String? userId, String? email}) async {
    await info(
      'Auth: $action',
      category: 'Authentication',
      metadata: {
        'userId': userId,
        'email': email,
      },
    );
  }

  /// Log notification event
  Future<void> logNotification({
    required String type,
    required String recipientId,
    String? title,
    String? body,
    bool? sent,
  }) async {
    await info(
      'Notification $type',
      category: 'Notification',
      metadata: {
        'recipientId': recipientId,
        'title': title,
        'body': body,
        'sent': sent,
      },
    );
  }

  /// Log API call
  Future<void> logApiCall({
    required String endpoint,
    required String method,
    int? statusCode,
    String? error,
  }) async {
    await (error != null ? this.error : info)(
      'API Call: $method $endpoint',
      category: 'API',
      metadata: {
        'endpoint': endpoint,
        'method': method,
        'statusCode': statusCode,
        'error': error,
      },
    );
  }

  /// Get logs for a specific user
  Stream<QuerySnapshot> getUserLogs(String userId, {int limit = 50}) {
    return _firestore
        .collection('logs')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Get logs by category
  Stream<QuerySnapshot> getLogsByCategory(String category, {int limit = 100}) {
    return _firestore
        .collection('logs')
        .where('category', isEqualTo: category)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Get error logs
  Stream<QuerySnapshot> getErrorLogs({int limit = 100}) {
    return _firestore
        .collection('logs')
        .where('level', isEqualTo: ERROR)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Clear old logs (call from Cloud Function)
  Future<void> clearOldLogs({int daysToKeep = 30}) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    final cutoffTimestamp = Timestamp.fromDate(cutoffDate);

    final oldLogs = await _firestore
        .collection('logs')
        .where('timestamp', isLessThan: cutoffTimestamp)
        .get();

    final batch = _firestore.batch();
    for (final doc in oldLogs.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
    print('Cleared ${oldLogs.docs.length} old logs');
  }
}
