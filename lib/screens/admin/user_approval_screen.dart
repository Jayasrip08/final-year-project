import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/notification_service.dart';
import '../../services/email_service.dart';
import '../../widgets/notification_badge.dart';
import '../notifications_screen.dart';

class UserApprovalScreen extends StatelessWidget {
  final Widget? drawer;
  const UserApprovalScreen({super.key, this.drawer});

  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  Future<void> _approveUser(BuildContext context, String uid, String name, String email, String role) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'approvalStatus': 'approved',
      });
      
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': uid,
        'title': 'Account Approved',
        'body': 'Congratulations! Your account has been approved. You can now access all features.',
        'type': 'account_approved',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'received': false,
      });
      
      // NEW: Send professional approval email
      await EmailService().sendApprovalEmail(
        studentEmail: email, 
        studentName: name, 
        role: role.toLowerCase()
      );
      
      if (context.mounted) {
        NotificationService.showSuccess("$name has been approved and notified!");
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectUser(BuildContext context, String uid, String name) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reject User"),
        content: Text("Are you sure you want to reject and delete $name? This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Reject & Delete"),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("User rejected and removed.")),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pending Approvals"),
        backgroundColor: customRed,
        foregroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        actions: [
          NotificationBadge(
            child: const Icon(Icons.notifications, color: Colors.white),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: drawer,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('approvalStatus', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 80, color: Colors.green[300]),
                  const SizedBox(height: 16),
                  const Text("All caught up! No pending approvals.", 
                    style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500)),
                ],
              ),
            );
          }

          final users = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index].data() as Map<String, dynamic>;
              final uid = users[index].id;
              final name = user['name'] ?? 'Unknown';
              final email = user['email'] ?? 'No Email';
              final role = (user['role'] ?? 'student').toString().toUpperCase();
              
              String details = '';
              if (role == 'STUDENT') {
                details = "Reg No: ${user['regNo'] ?? user['registerNo'] ?? 'N/A'}\nDept: ${user['dept'] ?? 'N/A'}";
              } else {
                details = "Emp ID: ${user['employeeId'] ?? 'N/A'}\nDept: ${user['dept'] ?? 'N/A'}";
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: customRed.withOpacity(0.2)),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar with role initial
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: customRed.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            role[0],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: customRed,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // User details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: customRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                role,
                                style: TextStyle(
                                  color: customRed,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              details,
                              style: TextStyle(color: Colors.grey[700], fontSize: 12, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      // Action buttons
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            tooltip: "Approve",
                            onPressed: () => _approveUser(context, uid, name, email, role),
                          ),
                          IconButton(
                            icon: Icon(Icons.cancel, color: customRed),
                            tooltip: "Reject",
                            onPressed: () => _rejectUser(context, uid, name),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}