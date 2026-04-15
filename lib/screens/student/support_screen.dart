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

class _SupportScreenState extends State<SupportScreen> with SingleTickerProviderStateMixin {
  final User _user = FirebaseAuth.instance.currentUser!;
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showRaiseTicketDialog() {
    final TextEditingController subjectCtrl = TextEditingController();
    final TextEditingController descCtrl = TextEditingController();
    String category = 'Technical';
    String dept = 'IT Support';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Raise Support Ticket", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 20),
                const Text("Category", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                DropdownButton<String>(
                  value: category,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: ['Technical', 'Financial', 'Academic', 'Others'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() {
                        category = val;
                        if (val == 'Technical') dept = 'IT Support';
                        else if (val == 'Financial') dept = 'Accounts Office';
                        else if (val == 'Academic') dept = 'Academic Cell';
                        else dept = 'General Admin';
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: subjectCtrl,
                  decoration: InputDecoration(
                    labelText: "Subject",
                    hintText: "Brief summary of the issue",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: "Detailed Description",
                    hintText: "Explain your concern in detail...",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (subjectCtrl.text.isEmpty || descCtrl.text.isEmpty) return;
                      
                      await FirebaseFirestore.instance.collection('support_tickets').add({
                        'uid': _user.uid,
                        'studentName': widget.userData['name'] ?? 'Student',
                        'regNo': widget.userData['regNo'] ?? 'N/A',
                        'category': category,
                        'department': dept,
                        'subject': subjectCtrl.text,
                        'description': descCtrl.text,
                        'status': 'open',
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Ticket raised successfully!"), backgroundColor: Colors.green)
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: customRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("SUBMIT TICKET", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
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
        title: Text('Help Center', style: TextStyle(color: customRed, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: customRed,
          unselectedLabelColor: Colors.grey,
          indicatorColor: customRed,
          tabs: const [
            Tab(text: "CONTACTS"),
            Tab(text: "MY TICKETS"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildContactsTab(),
          _buildTicketsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showRaiseTicketDialog,
        backgroundColor: customRed,
        icon: const Icon(Icons.add_comment_rounded, color: Colors.white),
        label: const Text("Raise Ticket", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildContactsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildInstitutionalHeader(),
        const SizedBox(height: 32),
        _sectionTitle("Primary Support Channels"),
        const SizedBox(height: 16),
        _buildSupportCategory("Accounts & Payments", "Fee queries, receipt issues, or bank transfers.", Icons.account_balance_rounded, Colors.blue, "accounting@apec.edu", "+91 94440 12345"),
        _buildSupportCategory("Technical Support", "Login issues, app bugs, or portal access.", Icons.computer_rounded, Colors.teal, "it.admin@apec.edu", "+91 94440 67890"),
        _buildSupportCategory("Academic Desk", "Scholarship, marksheet, or registration queries.", Icons.school_rounded, Colors.orange, "academic.cell@apec.edu", "+91 94440 54321"),
        const SizedBox(height: 32),
        _buildOfficeDetails(),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildTicketsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('support_tickets')
          .where('uid', isEqualTo: _user.uid)
          .orderBy('createdAt', descending: true)
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
                Icon(Icons.confirmation_number_outlined, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text("No Support Tickets Yet", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Text("Need help? Use the 'Raise Ticket' button below.", style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
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

  Widget _buildTicketCard(String docId, Map<String, dynamic> data) {
    final status = data['status'] ?? 'open';
    final Color statusColor = status == 'open' ? Colors.blue : (status == 'resolved' ? Colors.green : Colors.grey);
    
    String dateStr = '—';
    if (data['createdAt'] != null) {
      dateStr = DateFormat('dd MMM, hh:mm a').format((data['createdAt'] as Timestamp).toDate());
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ExpansionTile(
        title: Text(data['subject'] ?? 'No Subject', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Row(
          children: [
            Text(data['category'] ?? 'General', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(dateStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
              onPressed: () => _confirmDeleteTicket(docId),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const Text("Description:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Text(data['description'] ?? 'No description provided.', style: TextStyle(fontSize: 13, color: Colors.grey[800])),
                if (data['resolutionNote'] != null) ...[
                  const SizedBox(height: 12),
                  const Text("Admin Note:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green)),
                  const SizedBox(height: 4),
                  Text(data['resolutionNote'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Department: ${data['department']}", style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                    if (status == 'resolved')
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTicket(String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Ticket?"),
        content: const Text("Are you sure you want to remove this support ticket from your history?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.collection('support_tickets').doc(docId).delete();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Ticket deleted"))
                );
              }
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3436)));
  }

  Widget _buildInstitutionalHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: customRed,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: customRed.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Institutional Helpdesk", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Get direct support from Administrative and Technical teams of Adhiparasakthi Engineering College.", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildSupportCategory(String title, String desc, IconData icon, Color color, String email, String phone) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(desc, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _detailRow(Icons.alternate_email_rounded, email),
                const SizedBox(height: 8),
                _detailRow(Icons.phone_android_rounded, phone),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildOfficeDetails() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Walking Office Hours", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _officeRow("Mon - Fri", "09:00 AM - 04:30 PM"),
          _officeRow("Saturday", "09:00 AM - 12:30 PM"),
          _officeRow("Sunday", "Closed (Holiday)"),
          const Divider(height: 32),
          const Row(
            children: [
              Icon(Icons.location_on_rounded, color: Colors.grey, size: 18),
              SizedBox(width: 8),
              Text("Admin Block, Ground Floor", style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          )
        ],
      ),
    );
  }

  Widget _officeRow(String days, String hours) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(days, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(hours, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
