import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import '../services/notification_service.dart';

class ProfileScreen extends StatelessWidget {
  final Widget? drawer;
  final bool showLogout;
  const ProfileScreen({super.key, this.drawer, this.showLogout = true});

  // CUSTOM PROJECT COLOR
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

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
            child: Text('Logout', style: TextStyle(color: customRed)),
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
      backgroundColor: const Color(0xFFF8F9FA), // Slightly off-white for better card contrast
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
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
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: 20),
                
                // ── Modern Profile Header ──────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: customRed.withOpacity(0.2), width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: customRed.withOpacity(0.05),
                          child: Icon(Icons.person_rounded, size: 60, color: customRed),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: customRed,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          role.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // ── Information Sections ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoGroup(
                        title: "ACADEMIC DETAILS",
                        items: [
                          _profileTile(Icons.alternate_email_rounded, "Email Address", email),
                          if (role == 'student') ...[
                            _profileTile(Icons.account_balance_rounded, "Department", data['dept'] ?? 'N/A'),
                            _profileTile(Icons.fingerprint_rounded, "Register Number", data['regNo'] ?? 'N/A'),
                            _profileTile(Icons.event_note_rounded, "Current Batch", data['batch'] ?? 'N/A'),
                            _profileTile(Icons.workspace_premium_rounded, "Admission Quota", data['quotaCategory'] ?? 'N/A'),
                          ] else ...[
                            if (data['dept'] != null) _profileTile(Icons.account_balance_rounded, "Department", data['dept']),
                            _profileTile(Icons.badge_rounded, "Employee ID", data['employeeId'] ?? 'N/A'),
                          ],
                        ],
                      ),
                      
                      const SizedBox(height: 20),
                      
                      _buildInfoGroup(
                        title: "CONTACT & FINANCE",
                        items: [
                          if (role == 'student') ...[
                            _profileTile(Icons.phone_iphone_rounded, "Student Phone", data['phone'] ?? 'N/A'),
                            _profileTile(Icons.family_restroom_rounded, "Parent Phone", data['parentPhoneNumber'] ?? 'N/A'),
                            _profileTile(
                              Icons.account_balance_wallet_rounded, 
                              "Wallet Balance", 
                              FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance.collection('wallets').doc(user.uid).get(),
                                builder: (context, walletSnap) {
                                  double balance = 0.0;
                                  if (walletSnap.hasData && walletSnap.data!.exists) {
                                    balance = (walletSnap.data!.data() as Map<String, dynamic>?)?['balance']?.toDouble() ?? 0.0;
                                  } else {
                                    balance = (data['walletBalance'] as num?)?.toDouble() ?? 0.0;
                                  }
                                  return Text(
                                    "₹${balance.toStringAsFixed(0)}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: customRed,
                                    ),
                                  );
                                }
                              ),
                              isPrimary: true,
                            ),
                          ] else ...[
                            _profileTile(Icons.phone_iphone_rounded, "Contact Number", data['phone'] ?? 'N/A'),
                          ],
                        ],
                      ),

                      const SizedBox(height: 30),

                      // ── Logout Action ──────────────────────────────────────────
                      if (showLogout)
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => _logout(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: customRed.withOpacity(0.08),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              "LOGOUT FROM DEVICE",
                              style: TextStyle(
                                color: customRed,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoGroup({required String title, required List<Widget> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black45, letterSpacing: 1.1),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _profileTile(IconData icon, String label, dynamic value, {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[50]!, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPrimary ? customRed.withOpacity(0.1) : Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: isPrimary ? customRed : Colors.grey[600]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                value is Widget ? value : Text(
                  value.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isPrimary ? customRed : const Color(0xFF2D2D2D),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatStudentType(String? type) {
    if (type == null) return 'N/A';
    switch (type) {
      case 'day_scholar': return 'Day Scholar';
      case 'hosteller': return 'Hosteller';
      case 'bus_user': return 'Bus User';
      default: return type;
    }
  }
}