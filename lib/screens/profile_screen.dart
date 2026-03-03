import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import '../services/notification_service.dart';

class ProfileScreen extends StatelessWidget {
  final Widget? drawer;
  final bool showLogout;
  const ProfileScreen({super.key, this.drawer, this.showLogout = true});

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await NotificationService().deleteFCMToken();
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: drawer,
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("User profile not found."));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final role = data['role'] ?? 'user';
          final name = data['name'] ?? 'N/A';
          final email = data['email'] ?? user.email ?? 'N/A';

          return SingleChildScrollView(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(30),
                      bottomRight: Radius.circular(30),
                    ),
                  ),
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white,
                        child:
                            Icon(Icons.person, size: 60, color: Colors.indigo),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        role.toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.indigo[100],
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Account Information ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.badge, color: Colors.indigo),
                              SizedBox(width: 10),
                              Text(
                                "Account Information",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          _profileItem("Email", email),
                          _profileItem("Role", role.toUpperCase()),
                          if (role == 'student') ...[
                            _profileItem(
                                "Department", data['dept'] ?? 'N/A'),
                            _profileItem(
                                "Register No", data['regNo'] ?? 'N/A'),
                            _profileItem("Batch", data['batch'] ?? 'N/A'),
                            _profileItem(
                                "Parent's Phone", data['parentPhoneNumber'] ?? 'N/A'),
                            _profileItem(
                                "My Phone", data['phone'] ?? 'N/A'),
                            _profileItem(
                                "Quota", data['quotaCategory'] ?? 'N/A'),
                            _profileItem("Study Type",
                                _formatStudentType(data['studentType'])),
                            if (data['studentType'] == 'bus_user')
                              _profileItem(
                                  "Bus Point", data['busPlace'] ?? 'N/A'),
                            _profileItem(
                                "Wallet Balance", 
                                "₹${((data['walletBalance'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}",
                                color: Colors.green),
                          ] else if (role == 'staff' || role == 'admin') ...[
                            if (data['dept'] != null)
                              _profileItem("Department", data['dept']),
                            _profileItem(
                                "Employee ID", data['employeeId'] ?? 'N/A'),
                            if (data['employeeId'] != null && data['employeeId'].toString().isNotEmpty)
                              FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance.collection('staff_master_list').doc(data['employeeId']).get(),
                                builder: (context, staffSnapshot) {
                                  String displayPhone = data['phone'] ?? 'N/A';
                                  if (staffSnapshot.hasData && staffSnapshot.data!.exists) {
                                    displayPhone = staffSnapshot.data!['phone'] ?? displayPhone;
                                  }
                                  return _profileItem("Phone Number", displayPhone);
                                },
                              )
                            else
                              _profileItem("Phone Number", data['phone'] ?? 'N/A'),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // ── Security status ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    child: const ListTile(
                      leading: Icon(Icons.verified_user, color: Colors.green),
                      title: Text("Account Verified"),
                      subtitle:
                          Text("Your account is secured with email auth"),
                      trailing:
                          Icon(Icons.check_circle, color: Colors.green),
                    ),
                  ),
                ),

                if (showLogout) ...[
                  const SizedBox(height: 24),
                  // ── Logout Button ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _logout(context),
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: const Text(
                          'Logout',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Colors.red, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _profileItem(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.grey, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  String _formatStudentType(String? type) {
    if (type == null) return 'N/A';
    switch (type) {
      case 'day_scholar':
        return 'Day Scholar';
      case 'hosteller':
        return 'Hosteller';
      case 'bus_user':
        return 'Bus User';
      default:
        return type;
    }
  }
}
