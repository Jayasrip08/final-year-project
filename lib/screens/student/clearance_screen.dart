import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClearanceScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const ClearanceScreen({super.key, required this.userData});

  @override
  State<ClearanceScreen> createState() => _ClearanceScreenState();
}

class _ClearanceScreenState extends State<ClearanceScreen> {
  final User _user = FirebaseAuth.instance.currentUser!;
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);
  bool _isRequesting = false;

  Future<void> _initiateClearance() async {
    setState(() => _isRequesting = true);
    try {
      final docRef = FirebaseFirestore.instance.collection('clearance_requests').doc(_user.uid);
      
      await docRef.set({
        'uid': _user.uid,
        'studentName': widget.userData['name'] ?? '',
        'regNo': widget.userData['regNo'] ?? '',
        'dept': widget.userData['dept'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending', // Overall status
        'departments': {
          'library': 'pending',
          'labs': 'pending',
          'hostel': 'pending',
          'sports': 'pending',
          'accounts': 'pending',
        },
        'remarks': {},
      });
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initiate clearance: $e'), backgroundColor: customRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: customRed),
        title: Text(
          'Final Clearance',
          style: TextStyle(color: customRed, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('clearance_requests').doc(_user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final exists = snapshot.hasData && snapshot.data!.exists;

          if (!exists) {
            return _buildEmptyState();
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final depts = data['departments'] as Map<String, dynamic>? ?? {};
          final remarks = data['remarks'] as Map<String, dynamic>? ?? {};
          final overallStatus = data['status'] ?? 'pending';

          return RefreshIndicator(
            onRefresh: () async {}, // Stream auto-updates
            color: customRed,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildStatusBanner(overallStatus),
                const SizedBox(height: 24),
                const Text('Departmental Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 16),
                _buildDepartmentCard('Library', Icons.local_library_rounded, depts['library'], remarks['library']),
                _buildDepartmentCard('Laboratories', Icons.science_rounded, depts['labs'], remarks['labs']),
                _buildDepartmentCard('Hostel / Mess', Icons.hotel_rounded, depts['hostel'], remarks['hostel']),
                _buildDepartmentCard('Sports', Icons.sports_basketball_rounded, depts['sports'], remarks['sports']),
                _buildDepartmentCard('Accounts', Icons.account_balance_rounded, depts['accounts'], remarks['accounts']),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: customRed.withOpacity(0.06), shape: BoxShape.circle),
            child: Icon(Icons.outbox_rounded, size: 64, color: customRed.withOpacity(0.4)),
          ),
          const SizedBox(height: 20),
          const Text('No Clearance Requested', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Initiate the final clearance workflow to get approvals from all departments.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _isRequesting ? null : _initiateClearance,
            style: ElevatedButton.styleFrom(
              backgroundColor: customRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            icon: _isRequesting 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send_rounded, size: 18),
            label: const Text('Initiate Clearance', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(String status) {
    Color bg, textCol;
    String text;
    IconData icon;

    if (status == 'approved') {
      bg = Colors.green;
      textCol = Colors.white;
      text = 'COMPLETED';
      icon = Icons.verified_rounded;
    } else {
      bg = Colors.orange;
      textCol = Colors.white;
      text = 'PENDING APPROVALS';
      icon = Icons.hourglass_top_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: bg.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Icon(icon, color: textCol, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Overall Clearance Status", style: TextStyle(color: textCol.withOpacity(0.8), fontSize: 12)),
              const SizedBox(height: 4),
              Text(text, style: TextStyle(color: textCol, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentCard(String title, IconData icon, String? status, String? remark) {
    final s = status ?? 'pending';
    Color sColor = Colors.orange;
    IconData sIcon = Icons.pending_rounded;
    String sText = "Pending";

    if (s == 'approved') {
      sColor = Colors.green;
      sIcon = Icons.check_circle_rounded;
      sText = "Cleared";
    } else if (s == 'rejected') {
      sColor = customRed;
      sIcon = Icons.cancel_rounded;
      sText = "Blocked";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: Colors.blue, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: sColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(sIcon, color: sColor, size: 14),
                      const SizedBox(width: 4),
                      Text(sText, style: TextStyle(color: sColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            if (remark != null && remark.isNotEmpty) ...[
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.comment_rounded, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Remark: $remark',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}
