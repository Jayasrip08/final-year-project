import 'package:cloud_firestore/cloud_firestore.dart';
import 'sms_service.dart';

class EmailService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Send overdue payment reminder to a student using Firebase Trigger Email extension
  Future<bool> sendOverdueReminder({
    required String studentEmail,
    required String studentName,
    required String semester,
    required double dueAmount,
    required DateTime deadline,
  }) async {
    try {
      final emailBody = '''
Dear $studentName,

This is a reminder that your Semester $semester fee payment was due on ${_formatDate(deadline)}.

Outstanding Amount: ₹${dueAmount.toStringAsFixed(0)}

Please submit your payment proof at your earliest convenience through the A-DACS portal.

Thank you,
A-DACS Administration
''';

      final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: #3f51b5; color: white; padding: 20px; text-align: center; }
    .content { padding: 20px; background: #f9f9f9; }
    .amount { font-size: 24px; color: #f44336; font-weight: bold; }
    .footer { padding: 20px; text-align: center; color: #666; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h2>Payment Reminder</h2>
    </div>
    <div class="content">
      <p>Dear <strong>$studentName</strong>,</p>
      <p>This is a reminder that your <strong>Semester $semester</strong> fee payment was due on <strong>${_formatDate(deadline)}</strong>.</p>
      <p>Outstanding Amount: <span class="amount">₹${dueAmount.toStringAsFixed(0)}</span></p>
      <p>Please submit your payment proof at your earliest convenience through the A-DACS portal.</p>
    </div>
    <div class="footer">
      <p>Thank you,<br>A-DACS Administration</p>
    </div>
  </div>
</body>
</html>
''';

      // Add document to 'mail' collection - Firebase Trigger Email extension will process it
      await _db.collection('mail').add({
        'to': [studentEmail],
        'message': {
          'subject': 'Payment Reminder - Semester $semester Fee Due',
          'text': emailBody,
          'html': htmlBody,
        },
        'metadata': {
          'studentName': studentName,
          'semester': semester,
          'dueAmount': dueAmount,
          'sentAt': FieldValue.serverTimestamp(),
        },
      });

      return true;
    } catch (e) {
      print('Error sending email to $studentEmail: $e');
      return false;
    }
  }

  /// Send bulk reminders for all overdue students
  Future<Map<String, dynamic>> sendBulkOverdueReminders() async {
    int successCount = 0;
    int failureCount = 0;
    List<String> errors = [];

    try {
      // Get all overdue fee structures
      // Get all overdue fee structures
      // OPTIMIZATION: Filter deadline client-side to avoid composite index requirement
      final activeStructures = await _db
          .collection('fee_structures')
          .where('isActive', isEqualTo: true)
          .get();

      for (var feeDoc in activeStructures.docs) {
        final feeData = feeDoc.data();
        final Timestamp? ts = feeData['deadline'] as Timestamp?;
        if (ts == null) continue; // Skip if no deadline set
        
        final deadline = ts.toDate();
        
        // Skip if not yet overdue
        if (deadline.isAfter(DateTime.now())) continue;

        final dept = feeData['dept'] ?? '';
        final quota = feeData['quotaCategory'] ?? '';
        final semester = feeData['semester'] ?? '';
        final totalAmount = (feeData['totalAmount'] ?? 0).toDouble();

        // Get students matching this fee structure
        Query<Map<String, dynamic>> studentsQuery = _db
            .collection('users')
            .where('role', isEqualTo: 'student');
            
        if (dept != 'All') {
          studentsQuery = studentsQuery.where('dept', isEqualTo: dept);
        }

        final students = await studentsQuery.get();

        for (var studentDoc in students.docs) {
          final studentData = studentDoc.data();
          final studentQuota = (studentData['quotaCategory'] ?? '').toString().toLowerCase();
          
          // Skip if quota doesn't match (unless it's "All")
          if (quota != 'All' && studentQuota != quota.toLowerCase()) {
            continue;
          }

          final studentId = studentDoc.id;
          final studentEmail = studentData['email'] ?? '';
          final studentName = studentData['name'] ?? 'Student';

          // Check if student has paid
          final payments = await _db
              .collection('payments')
              .where('studentId', isEqualTo: studentId)
              .where('semester', isEqualTo: semester)
              .where('status', isEqualTo: 'verified')
              .get();

          double paidAmount = 0.0;
          for (var payment in payments.docs) {
            paidAmount += (payment['amount'] as num).toDouble();
          }

          // Only send reminder if there's a due amount
          if (paidAmount < totalAmount && studentEmail.isNotEmpty) {
            final dueAmount = totalAmount - paidAmount;
            
            try {
              final success = await sendOverdueReminder(
                studentEmail: studentEmail,
                studentName: studentName,
                semester: semester,
                dueAmount: dueAmount,
                deadline: deadline,
              );

              if (success) {
                successCount++;
              } else {
                failureCount++;
              }

              // NEW: Also send SMS reminder to parent
              if (studentData['parentPhoneNumber'] != null) {
                await SMSService().sendManualOverdueSMS(
                  studentId: studentId,
                  amount: dueAmount,
                  deadline: deadline,
                  silent: true, // Don't show success snackbar for every single student
                );
              }
            } catch (e) {
              failureCount++;
              errors.add('$studentName: $e');
            }
          }
        }
      }
    } catch (e) {
      errors.add('System error: $e');
    }

    return {
      'success': successCount,
      'failed': failureCount,
      'errors': errors,
    };
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
