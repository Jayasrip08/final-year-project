import 'package:cloud_firestore/cloud_firestore.dart';
import 'sms_service.dart';

class EmailService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Corporate Red Color from APEC Branding
  static const String _primaryRed = '#C6372D';
  

  /// Professional HTML Template Wrapper
  String _wrapWithProfessionalTemplate({
    required String title,
    required String contentHtml,
  }) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: 'Segoe UI', Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; background-color: #f4f6f9; }
    .wrapper { width: 100%; padding: 40px 0; }
    .container { max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.05); }
    .header { background: $_primaryRed; color: white; padding: 30px; text-align: center; }
    .content { padding: 40px; }
    .content h1 { font-size: 22px; color: #2d3436; margin-top: 0; }
    .content p { font-size: 15px; color: #636e72; }
    .highlight-box { background: #fffcfc; border-left: 4px solid $_primaryRed; padding: 20px; margin: 25px 0; border-radius: 0 8px 8px 0; }
    .amount { font-size: 24px; color: $_primaryRed; font-weight: bold; }
    .footer { padding: 30px; background: #fafafa; border-top: 1px solid #eeeeee; color: #95a5a6; font-size: 11px; text-align: center; }
    .footer strong { color: #7f8c8d; }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="container">
      <div class="header">
        <h2 style="margin:0; letter-spacing: 1px;">A-DACS</h2>
      </div>
      <div class="content">
        $contentHtml
      </div>
      <div class="footer">
        <p><strong>Adhiparasakthi Engineering College (APEC)</strong></p>
        <p>Admin Block, Ground Floor | Melmaruvathur, Tamil Nadu 603319</p>
        <p>Contact: +91 94440 12345 | accounting@apec.edu</p>
        <div style="margin-top:20px; color: #bdc3c7;">&copy; ${DateTime.now().year} Institutional Digital Clearance System</div>
      </div>
    </div>
  </div>
</body>
</html>
''';
  }

  /// Send overdue payment reminder to a student using Firebase Trigger Email extension
  Future<bool> sendOverdueReminder({
    required String studentEmail,
    required String studentName,
    required String semester,
    required double dueAmount,
    required DateTime deadline,
  }) async {
    try {
      final contentHtml = '''
        <h1>Fee Payment Reminder</h1>
        <p>Dear <strong>$studentName</strong>,</p>
        <p>This is a formal reminder regarding your outstanding dues for the current academic session.</p>
        <div class="highlight-box">
          <p style="margin:0; font-size:12px; text-transform:uppercase; letter-spacing:1px; color:#b2bec3;">Outstanding Balance</p>
          <div class="amount">₹${dueAmount.toStringAsFixed(0)}</div>
          <p style="margin:5px 0 0 0; color:#e17055;"><strong>Due Date: ${_formatDate(deadline)}</strong></p>
        </div>
        <p>Please note that your payment for <strong>Semester $semester</strong> is currently overdue. We request you to upload the payment proof through the A-DACS mobile portal or visit the accounts office immediately to avoid late fee penalties.</p>
        <p>If you have already made the payment, please ensure the transfer details are updated in the app for verification.</p>
        <p>Sincerely,<br><strong>Institutional Accounts Department</strong></p>
      ''';

      final htmlBody = _wrapWithProfessionalTemplate(
        title: 'Payment Reminder - Semester $semester', 
        contentHtml: contentHtml
      );

      final plainText = 'Dear $studentName, your Semester $semester fee of ₹${dueAmount.toStringAsFixed(0)} was due on ${_formatDate(deadline)}. Please submit proof in the A-DACS app. Thank you, A-DACS Admin.';

      // Add document to 'mail' collection - Firebase Trigger Email extension will process it
      await _db.collection('mail').add({
        'to': [studentEmail],
        'message': {
          'subject': 'Fee Payment Reminder - Semester $semester',
          'text': plainText,
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

  /// Send account approval email
  Future<bool> sendApprovalEmail({
    required String studentEmail,
    required String studentName,
    required String role,
  }) async {
    try {
      final contentHtml = '''
        <h1>Account Approved</h1>
        <p>Dear <strong>$studentName</strong>,</p>
        <p>We are pleased to inform you that your registration for the <strong>Institutional Digital Clearance System (A-DACS)</strong> has been verified and approved by the administration.</p>
        <div class="highlight-box">
          <p style="margin:0;"><strong>You can now log in to the application to:</strong></p>
          <ul style="margin:10px 0; color:#636e72;">
            <li>View fee structures and payment history</li>
            <li>Submit semester clearance requests</li>
            <li>Access institutional support channels</li>
          </ul>
        </div>
        <p>Please use your registered email and password to access your dashboard. We recommend keeping your profile details updated for seamless communication.</p>
        <p>Welcome aboard!<br><strong>A-DACS Administration</strong></p>
      ''';

      final htmlBody = _wrapWithProfessionalTemplate(
        title: 'Account Approval Notification', 
        contentHtml: contentHtml
      );

      await _db.collection('mail').add({
        'to': [studentEmail],
        'message': {
          'subject': 'A-DACS Account Approved - Welcome',
          'text': 'Dear $studentName, your A-DACS account has been approved. You can now log in to access your dashboard. Welcome!',
          'html': htmlBody,
        },
        'metadata': {
          'studentName': studentName,
          'type': 'approval',
          'sentAt': FieldValue.serverTimestamp(),
        },
      });
      return true;
    } catch (e) {
      print('Error sending approval email: $e');
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
          // The student document uses 'quota', but the fee structure uses 'quotaCategory'
          final studentQuota = (studentData['quota'] ?? studentData['quotaCategory'] ?? '').toString().toLowerCase();
          
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
