import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class SupportScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const SupportScreen({super.key, required this.userData});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final User _user = FirebaseAuth.instance.currentUser!;
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  final TextEditingController _issueController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  bool _isSubmitting = false;

  void _showRaiseTicketDialog() {
    _issueController.clear();
    _descController.clear();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Raise Support Ticket", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _issueController,
              decoration: const InputDecoration(
                labelText: "Issue Title (e.g. Payment failed)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: "Description",
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          StatefulBuilder(
            builder: (context, setStateDialog) {
              return ElevatedButton(
                onPressed: _isSubmitting ? null : () async {
                  if (_issueController.text.trim().isEmpty || _descController.text.trim().isEmpty) return;
                  
                  setStateDialog(() => _isSubmitting = true);
                  try {
                    await FirebaseFirestore.instance.collection('support_tickets').add({
                      'uid': _user.uid,
                      'studentName': widget.userData['name'] ?? 'Unknown',
                      'regNo': widget.userData['regNo'] ?? '',
                      'title': _issueController.text.trim(),
                      'description': _descController.text.trim(),
                      'status': 'open',
                      'createdAt': FieldValue.serverTimestamp(),
                      'adminReply': null,
                    });
                    if (mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  } finally {
                    setStateDialog(() => _isSubmitting = false);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: customRed, foregroundColor: Colors.white),
                child: _isSubmitting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Submit"),
              );
            }
          ),
        ],
      ),
    );
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
        title: Text('Help & Support', style: TextStyle(color: customRed, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildEmergencyContacts(),
          const SizedBox(height: 32),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('My Tickets', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
              ElevatedButton.icon(
                onPressed: _showRaiseTicketDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: customRed,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: customRed.withOpacity(0.3))
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text("New Ticket", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              )
            ],
          ),
          const SizedBox(height: 16),
          
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('support_tickets')
                .where('uid', isEqualTo: _user.uid)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[200]!)),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text("No active tickets", style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: docs.map((doc) => _buildTicketCard(doc.data() as Map<String, dynamic>)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyContacts() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: customRed,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: customRed.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.headset_mic_rounded, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Text('Emergency Contacts', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          _contactItem(Icons.account_balance_rounded, 'Accounts Office', 'accounting@apec.edu'),
          const Divider(color: Colors.white24, height: 24),
          _contactItem(Icons.computer_rounded, 'IT Support', 'it.admin@apec.edu'),
          const Divider(color: Colors.white24, height: 24),
          _contactItem(Icons.phone_rounded, 'Helpdesk Phone', '+91 80000 12345'),
        ],
      ),
    );
  }

  Widget _contactItem(IconData icon, String title, String detail) {
    return Row(
      children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: Colors.white, size: 16)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text(detail, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        )
      ],
    );
  }

  Widget _buildTicketCard(Map<String, dynamic> data) {
    String status = data['status'] ?? 'open';
    Color sColor = status == 'open' ? Colors.orange : status == 'resolved' ? Colors.green : Colors.blue;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(data['title'] ?? 'Ticket', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: sColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(status.toUpperCase(), style: TextStyle(color: sColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(data['description'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            if (data['adminReply'] != null && data['adminReply'].toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), border: Border(left: BorderSide(color: Colors.blue, width: 4))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.admin_panel_settings_rounded, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(child: Text("Admin: ${data['adminReply']}", style: TextStyle(color: Colors.grey[800], fontSize: 13))),
                  ],
                ),
              )
            ],
            const SizedBox(height: 12),
            if (data['createdAt'] != null)
              Text(
                DateFormat('dd MMM yyyy, hh:mm a').format((data['createdAt'] as Timestamp).toDate()),
                style: TextStyle(color: Colors.grey[400], fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}
