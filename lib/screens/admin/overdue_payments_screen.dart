import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../widgets/deadline_widget.dart';
import '../../services/email_service.dart';
import '../../widgets/notification_badge.dart';
import '../notifications_screen.dart';
import '../../services/sms_service.dart';
import '../../services/notification_service.dart';

class OverduePaymentsScreen extends StatefulWidget {
  final Widget? drawer;
  const OverduePaymentsScreen({super.key, this.drawer});

  @override
  State<OverduePaymentsScreen> createState() => _OverduePaymentsScreenState();
}

class _OverduePaymentsScreenState extends State<OverduePaymentsScreen> {
  bool _isSendingReminders = false;

  Future<void> _sendBulkReminders() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Fee Reminders'),
        content: const Text(
          'This will send automated Email and SMS reminders to all students with overdue payments. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            child: const Text('Send Reminders'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSendingReminders = true);

    try {
      final result = await EmailService().sendBulkOverdueReminders();
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reminders Sent'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('✅ Successfully sent: ${result['success']}'),
                if (result['failed'] > 0)
                  Text('❌ Failed: ${result['failed']}', style: const TextStyle(color: Colors.red)),
                if ((result['errors'] as List).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...(result['errors'] as List).take(3).map((e) => Text('• $e', style: const TextStyle(fontSize: 12))),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending reminders: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingReminders = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overdue Payments'),
        backgroundColor: Colors.indigo,
        actions: [
          NotificationBadge(
            child: const Icon(Icons.notifications),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: widget.drawer,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSendingReminders ? null : _sendBulkReminders,
        backgroundColor: Colors.orange,
        icon: _isSendingReminders 
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.email_outlined, size: 20),
                  SizedBox(width: 4),
                  Icon(Icons.sms_outlined, size: 20),
                ],
              ),
        label: Text(_isSendingReminders ? 'Sending...' : 'Send Reminders'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('fee_structures')
            .where('isActive', isEqualTo: true)
            .snapshots(),
        builder: (context, feeSnapshot) {
          if (feeSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!feeSnapshot.hasData || feeSnapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No active fee structures"));
          }

          // Client-side filter for overdue items
          final overdueFees = feeSnapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final Timestamp? ts = data['deadline'] as Timestamp?;
            if (ts == null) return false; // No deadline = not overdue
            return ts.toDate().isBefore(DateTime.now());
          }).toList();

          if (overdueFees.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.check_circle, size: 64, color: Colors.green),
                   SizedBox(height: 16),
                   Text('No overdue payments!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: overdueFees.length,
            itemBuilder: (context, index) {
              final feeData = overdueFees[index].data() as Map<String, dynamic>;
              final Timestamp? ts = feeData['deadline'] as Timestamp?;
              final DateTime deadline = ts?.toDate() ?? DateTime.now();
              final dept = feeData['dept'] ?? '';
              final quota = feeData['quotaCategory'] ?? '';
              final amount = feeData['totalAmount'] ?? feeData['amount'] ?? 0;
              final semester = feeData['semester'] ?? '';
              final academicYear = feeData['academicYear'] ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.red.shade300, width: 2),
                ),
                child: ExpansionTile(
                  leading: const Icon(Icons.error, color: Colors.red, size: 32),
                  title: Text(
                    '$dept - $quota',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Amount: ₹$amount'),
                      Text(
                        'Deadline: ${DateFormat('dd MMM yyyy').format(deadline)}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DeadlineBadge(deadline: deadline),
                          const SizedBox(height: 16),
                          Text(
                            'Academic Year: $academicYear',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'Semester: $semester',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          const Text(
                            'Students with Overdue Payments:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildOverdueStudentsList(dept, quota, semester, (amount as num).toDouble(), deadline),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOverdueStudentsList(String dept, String quota, String semester, double totalFeeAmount, DateTime deadline) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'student');

    // Only filter by Dept if it's NOT 'All'
    if (dept != 'All') {
      query = query.where('dept', isEqualTo: dept);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, studentSnapshot) {
        if (!studentSnapshot.hasData) {
          return const CircularProgressIndicator();
        }

        var students = studentSnapshot.data!.docs;
        
        // Manual Filter for Quota (Case Insensitive)
        if (quota != 'All') {
          students = students.where((s) {
            final q = (s['quotaCategory'] ?? '').toString().toLowerCase();
            return q == quota.toLowerCase();
          }).toList();
        }

        if (students.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('No students found in $dept ($quota)'),
          );
        }

        return Column(
          children: students.map((studentDoc) {
            final studentData = studentDoc.data() as Map<String, dynamic>;
            final studentId = studentDoc.id;

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('payments')
                  .where('studentId', isEqualTo: studentId)
                  .where('semester', isEqualTo: semester)
                  .where('status', isEqualTo: 'verified')
                  .snapshots(),
              builder: (context, paymentSnapshot) {
                // Calculate Total Verified Paid Amount
                double paidAmount = 0.0;
                if (paymentSnapshot.hasData) {
                   for (var doc in paymentSnapshot.data!.docs) {
                     paidAmount += (doc['amount'] as num).toDouble();
                   }
                }

                bool isOverdue = paidAmount < totalFeeAmount;

                // Only show students who have LESS than the required fee (Dues > 0)
                if (!isOverdue) {
                  return const SizedBox.shrink();
                }
                
                double dueAmount = totalFeeAmount - paidAmount;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Colors.red.shade50,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.red,
                      child: Text(
                        (studentData['name'] ?? "S")[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(studentData['name'] ?? "Unknown"),
                    subtitle: Text('Reg: ${studentData['regNo']}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Icon(Icons.warning, color: Colors.red, size: 16),
                        Text(
                          "Due: ₹${dueAmount.toStringAsFixed(0)}", 
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}
