import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class SupportInboxScreen extends StatefulWidget {
  final Widget? drawer; // For Admin side menu integration
  const SupportInboxScreen({super.key, this.drawer});

  @override
  State<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

class _SupportInboxScreenState extends State<SupportInboxScreen> {
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);
  final User? _user = FirebaseAuth.instance.currentUser;
  String _userRole = 'staff'; // Default, will fetch
  bool _isAdmin = false;
  String? _staffDept;

  @override
  void initState() {
    super.initState();
    _fetchUserContext();
  }

  Future<void> _fetchUserContext() async {
    if (_user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(_user!.uid).get();
    if (doc.exists) {
      if (mounted) {
        setState(() {
          _userRole = doc.data()?['role'] ?? 'staff';
          _isAdmin = _userRole == 'admin';
          _staffDept = doc.data()?['dept'];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) return const Scaffold(body: Center(child: Text("Not Logged In")));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      drawer: widget.drawer,
      appBar: AppBar(
        title: const Text("Support Inbox", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: customRed,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _staffDept == null && !_isAdmin 
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    color: customRed,
                    child: const TabBar(
                      indicatorColor: Colors.white,
                      indicatorWeight: 3,
                      labelStyle: TextStyle(fontWeight: FontWeight.bold),
                      unselectedLabelColor: Colors.white70,
                      labelColor: Colors.white,
                      tabs: [
                        Tab(text: "Active Tickets"),
                        Tab(text: "Resolved"),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTicketList(active: true),
                        _buildTicketList(active: false),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTicketList({required bool active}) {
    Query query = FirebaseFirestore.instance.collection('support_tickets');

    // Filter by status
    if (active) {
      query = query.where('status', whereIn: ['open', 'in_progress']);
    } else {
      query = query.where('status', isEqualTo: 'resolved');
    }

    // Filter by Role Scope
    if (!_isAdmin) {
      // Staff view: only assigned students (standard for now)
      // Actually, since we want Staff to manage, we'll follow the rule:
      // only read if assigned. But Firestore Query cannot check 'isAssigned' easily in a where().
      // Instead, we will filter by DEPT if Staff, then filter results in memory or via assignment link.
      // If we use the 'assigned' model, we need to handle that. 
      // For now, let's filter by staffDept if available.
      if (_staffDept != null) {
        query = query.where('dept', isEqualTo: _staffDept);
      }
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (snapshot.error.toString().contains('index')) {
            return _buildIndexError();
          }
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(active ? Icons.inbox : Icons.done_all, size: 60, color: Colors.grey[300]),
                const SizedBox(height: 10),
                Text(
                  active ? "No active tickets found." : "No resolved tickets yet.",
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildTicketCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildTicketCard(String id, Map<String, dynamic> data) {
    final DateTime? date = (data['createdAt'] as Timestamp?)?.toDate();
    final String dateStr = date != null ? DateFormat('dd MMM, hh:mm a').format(date) : "Unknown date";
    final String status = data['status'] ?? 'open';
    final String category = data['category'] ?? 'General';
    final String studentName = data['studentName'] ?? 'Anonymous';

    Color statusColor;
    if (status == 'open') statusColor = Colors.red;
    else if (status == 'in_progress') statusColor = Colors.orange;
    else statusColor = Colors.green;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: PageStorageKey(id),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(_getIconForCategory(category), color: statusColor, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                studentName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
              ),
            ),
          ],
        ),
        subtitle: Text("$category • $dateStr", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const Text("Message:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(data['message'] ?? "No message detail provided.", style: const TextStyle(height: 1.5)),
                if (data['resolutionNote'] != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Resolution Note:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(data['resolutionNote'], style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (status != 'resolved')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (status == 'open')
                        OutlinedButton.icon(
                          onPressed: () => _updateStatus(id, 'in_progress'),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text("Pick Up"),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showResolveDialog(id),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text("Resolve"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'technical': return Icons.computer_rounded;
      case 'financial': return Icons.account_balance_wallet_rounded;
      case 'academic': return Icons.school_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await FirebaseFirestore.instance.collection('support_tickets').doc(id).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        'handledBy': _user!.uid,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error updating ticket: $e")));
    }
  }

  void _showResolveDialog(String id) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Resolve Ticket"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Provide a brief resolution note for the student:"),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: "e.g. Issue resolved in database. Please check again.",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final note = noteController.text.trim();
              if (note.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please add a resolution note")));
                return;
              }
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.collection('support_tickets').doc(id).update({
                'status': 'resolved',
                'resolutionNote': note,
                'resolvedAt': FieldValue.serverTimestamp(),
                'handledBy': _user!.uid,
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text("Mark as Resolved"),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 50),
            const SizedBox(height: 16),
            const Text(
              "Index Deployment Required",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              "Please run 'firebase deploy --only firestore:indexes' in your terminal to enable this view.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
