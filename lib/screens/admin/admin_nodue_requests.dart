import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminNoDueRequestsScreen extends StatelessWidget {
  final Widget? drawer;
  const AdminNoDueRequestsScreen({super.key, this.drawer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("No-Due Reissue Requests"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      drawer: drawer,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('no_due_certificates')
            .where('status', isEqualTo: 'reissue_requested')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_outlined, size: 80, color: Colors.green[300]),
                  const SizedBox(height: 16),
                  const Text("No pending reissue requests", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final requestedAt = data['reissueRequestedAt'] != null
                  ? DateFormat('dd MMM yyyy, hh:mm a').format((data['reissueRequestedAt'] as Timestamp).toDate())
                  : 'N/A';

              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.orangeAccent,
                            child: Icon(Icons.description, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['studentName'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text("Reg No: ${data['regNo'] ?? '-'}  |  Dept: ${data['dept'] ?? '-'}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              border: Border.all(color: Colors.orange),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text("Sem ${data['semester'] ?? '-'}", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Batch: ${data['batch'] ?? '-'}", style: const TextStyle(fontSize: 13)),
                              Text("Requested: $requestedAt", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _handleRequest(context, doc.id, 'issued', 'Rejected'),
                                icon: const Icon(Icons.close, size: 16),
                                label: const Text("Reject"),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () => _handleRequest(context, doc.id, 'reissue_approved', 'Approved'),
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text("Approve"),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              ),
                            ],
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

  Future<void> _handleRequest(BuildContext context, String docId, String newStatus, String actionLabel) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$actionLabel Request?"),
        content: Text("Are you sure you want to $actionLabel this No-Due reissue request?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: newStatus == 'reissue_approved' ? Colors.green : Colors.red),
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final Map<String, dynamic> updateData = {
      'status': newStatus,
    };

    if (newStatus == 'reissue_approved') {
      updateData['reissueApprovedAt'] = FieldValue.serverTimestamp();
    }

    await FirebaseFirestore.instance
        .collection('no_due_certificates')
        .doc(docId)
        .update(updateData);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Request $actionLabel successfully"),
          backgroundColor: newStatus == 'reissue_approved' ? Colors.green : Colors.red,
        ),
      );
    }
  }
}
