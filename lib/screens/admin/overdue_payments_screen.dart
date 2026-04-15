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
  final Color primaryRed = const Color(0xFFD32F2F); // A-DACS Corporate Red

  Future<void> _sendBulkReminders() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: primaryRed),
            const SizedBox(width: 10),
            const Text('Send Fee Reminders'),
          ],
        ),
        content: const Text(
          'This will send automated Email and SMS reminders to all students with overdue payments. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Send Reminders', style: TextStyle(color: Colors.white)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text('Reminders Processed'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _resultRow(Icons.check_circle, 'Success: ${result['success']}', Colors.green),
                if (result['failed'] > 0)
                  _resultRow(Icons.error, 'Failed: ${result['failed']}', primaryRed),
                if ((result['errors'] as List).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Error Details:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Divider(),
                  ...(result['errors'] as List).take(2).map((e) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $e', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  )),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: primaryRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingReminders = false);
    }
  }

  Widget _resultRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 8), Text(text)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Overdue Payments', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          NotificationBadge(
            child: const Icon(Icons.notifications),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      drawer: widget.drawer,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSendingReminders ? null : _sendBulkReminders,
        backgroundColor: _isSendingReminders ? Colors.grey : Colors.orange[800],
        elevation: 4,
        icon: _isSendingReminders 
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.send_rounded, size: 20),
        label: Text(_isSendingReminders ? 'PROCESSING...' : 'SEND REMINDERS', 
                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
      ),
      body: Column(
        children: [
          // Red Header Accent
          Container(
            height: 20,
            decoration: BoxDecoration(
              color: primaryRed,
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('fee_structures')
                  .where('isActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, feeSnapshot) {
                if (feeSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFFD32F2F))));
                }

                if (!feeSnapshot.hasData || feeSnapshot.data!.docs.isEmpty) {
                  return _buildEmptyState(Icons.info_outline, "No active fee structures");
                }

                final overdueFees = feeSnapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final Timestamp? ts = data['deadline'] as Timestamp?;
                  if (ts == null) return false;
                  return ts.toDate().isBefore(DateTime.now());
                }).toList();

                if (overdueFees.isEmpty) {
                  return _buildEmptyState(Icons.check_circle_outline, 'No overdue payments found!');
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
                  itemCount: overdueFees.length,
                  itemBuilder: (context, index) {
                    final feeData = overdueFees[index].data() as Map<String, dynamic>;
                    final Timestamp? ts = feeData['deadline'] as Timestamp?;
                    final DateTime deadline = ts?.toDate() ?? DateTime.now();
                    final dept = feeData['dept'] ?? '';
                    final quota = feeData['quotaCategory'] ?? '';
                    final amount = feeData['totalAmount'] ?? feeData['amount'] ?? 0;
                    final semester = feeData['semester'] ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          iconColor: primaryRed,
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: primaryRed.withOpacity(0.1), shape: BoxShape.circle),
                            child: Icon(Icons.assignment_late_outlined, color: primaryRed, size: 24),
                          ),
                          title: Text('$dept - $quota', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          subtitle: Text(
                            'Deadline: ${DateFormat('dd MMM yyyy').format(deadline)}',
                            style: TextStyle(color: primaryRed, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10)),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Sem: $semester', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text('Structure Fee: ₹$amount', style: TextStyle(color: primaryRed, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                  const Text('PENDING STUDENTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.1)),
                                  const Divider(),
                                  _buildOverdueStudentsList(dept, quota, semester, (amount as num).toDouble(), deadline),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 70, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildOverdueStudentsList(String dept, String quota, String semester, double totalFeeAmount, DateTime deadline) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'student');
    if (dept != 'All') query = query.where('dept', isEqualTo: dept);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, studentSnapshot) {
        if (!studentSnapshot.hasData) return const Center(child: LinearProgressIndicator());

        var students = studentSnapshot.data!.docs;
        if (quota != 'All') {
          students = students.where((s) {
            final data = s.data() as Map<String, dynamic>;
            // The student document uses 'quota', but the fee structure uses 'quotaCategory'
            final q = (data['quota'] ?? data['quotaCategory'] ?? '').toString().toLowerCase();
            return q == quota.toLowerCase();
          }).toList();
        }

        if (students.isEmpty) return const Padding(padding: EdgeInsets.all(8.0), child: Text('No students matched criteria.'));

        return Column(
          children: students.map((studentDoc) {
            final studentData = studentDoc.data() as Map<String, dynamic>;
            
            // Optimized: Fetching payments as a single stream for that student & semester
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('payments')
                  .where('studentId', isEqualTo: studentDoc.id)
                  .where('semester', isEqualTo: semester)
                  .snapshots(),
              builder: (context, paymentSnapshot) {
                if (paymentSnapshot.hasError) return const SizedBox.shrink();
                
                double paidAmount = 0.0;
                if (paymentSnapshot.hasData) {
                  // LOCAL FILTERING: Filter by status: 'verified' here to reduce composite index needs
                  for (var doc in paymentSnapshot.data!.docs) {
                    final pData = doc.data() as Map<String, dynamic>;
                    if (pData['status'] == 'verified') {
                      paidAmount += (pData['amount'] ?? 0).toDouble();
                    }
                  }
                }

                if (paidAmount >= totalFeeAmount) return const SizedBox.shrink();
                
                double dueAmount = totalFeeAmount - paidAmount;

                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade50),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: primaryRed,
                      child: Text((studentData['name'] ?? "S")[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                    title: Text(studentData['name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Reg: ${studentData['regNo']} • Sem $semester'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("DUE", style: TextStyle(color: primaryRed, fontSize: 10, fontWeight: FontWeight.bold)),
                        Text("₹${dueAmount.toStringAsFixed(0)}", style: TextStyle(color: primaryRed, fontWeight: FontWeight.bold, fontSize: 14)),
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