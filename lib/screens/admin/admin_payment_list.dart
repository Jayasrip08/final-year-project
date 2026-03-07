import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/fee_service.dart';
import 'verification_screen.dart';

class PaymentListTab extends StatefulWidget {
  final bool isPending;

  const PaymentListTab({super.key, required this.isPending});

  @override
  State<PaymentListTab> createState() => _PaymentListTabState();
}

class _PaymentListTabState extends State<PaymentListTab> with AutomaticKeepAliveClientMixin {
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    Query query = FirebaseFirestore.instance.collection('payments');
    
    if (widget.isPending) {
      query = query.where('status', isEqualTo: 'under_review');
    } else {
      query = query.where('status', whereIn: ['verified', 'rejected']);
    }

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: "Search by Reg No...",
              prefixIcon: Icon(Icons.search, color: customRed),
              suffixIcon: _searchQuery.isNotEmpty 
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = "");
                    })
                : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: customRed, width: 2),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: query.orderBy('submittedAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SelectableText(
                      "Error: ${snapshot.error}",
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.isPending ? Icons.inbox_outlined : Icons.history_edu_outlined, 
                        size: 80, 
                        color: Colors.grey[300]
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.isPending ? "No pending approvals" : "No payment history",
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              }

              final filteredDocs = snapshot.data!.docs.where((doc) {
                if (_searchQuery.isEmpty) return true;
                final data = doc.data() as Map<String, dynamic>;
                final regNo = (data['studentRegNo'] ?? data['uid'] ?? '').toString().toLowerCase();
                final name = (data['studentName'] ?? '').toString().toLowerCase();
                return regNo.contains(_searchQuery) || name.contains(_searchQuery);
              }).toList();

              if (filteredDocs.isEmpty) {
                return const Center(child: Text("No matching records found"));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  var doc = filteredDocs[index];
                  var data = doc.data() as Map<String, dynamic>;
                  
                  String studentName = data['studentName'] ?? 'Unknown Student';
                  String regNo = data['studentRegNo'] ?? data['uid'] ?? 'No RegNo';
                  String dept = data['dept'] ?? 'Gen';
                  double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                  String transactionId = data['transactionId'] ?? 'Manual';
                  String feeType = data['feeType'] ?? 'Fee';
                  String status = data['status'] ?? '';
                  
                  Timestamp? submittedAt = data['submittedAt'] as Timestamp?;
                  String dateStr = submittedAt != null 
                      ? DateFormat('dd MMM, hh:mm a').format(submittedAt.toDate())
                      : 'Just now';

                  Color statusColor;
                  IconData statusIcon;
                  
                  if (status == 'verified') {
                    statusColor = Colors.green[700]!;
                    statusIcon = Icons.verified;
                  } else if (status == 'rejected') {
                    statusColor = customRed;
                    statusIcon = Icons.error_outline;
                  } else {
                    statusColor = Colors.orange[800]!;
                    statusIcon = Icons.pending_actions;
                  }

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: customRed.withOpacity(0.2)),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                         if (widget.isPending) {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => VerificationScreen(
                                data: data, 
                                docId: doc.id, 
                                studentId: data['uid']
                              )
                            ));
                         } else {
                            _showRevertDialog(context, doc.id, status);
                         }
                      }, 
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Avatar
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: customRed.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      studentName[0].toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: customRed,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Student Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        studentName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "$regNo  •  $dept",
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                                // Installment Chip
                                if (data['isInstallment'] == true)
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      "INST ${data['installmentNumber'] ?? '?'}",
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                // Status Chip
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: statusColor.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(statusIcon, size: 14, color: statusColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        feeType,
                                        style: TextStyle(color: Colors.grey[700], fontSize: 13),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "₹${amount.toStringAsFixed(0)}",
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: customRed,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.receipt_long, size: 12, color: Colors.grey[500]),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              transactionId,
                                              style: TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (data['ocrVerified'] == true) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.green[50],
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.green[200]!),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.document_scanner, size: 10, color: Colors.green[700]),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    "OCR Verified",
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.green[800],
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      dateStr,
                                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                    ),
                                    const SizedBox(height: 8),
                                    if (widget.isPending || status == 'verified' || status == 'rejected')
                                      Row(
                                        children: [
                                          Text(
                                            widget.isPending ? "Review" : "Revert",
                                            style: TextStyle(
                                              color: widget.isPending ? Colors.blue[700] : customRed,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            widget.isPending ? Icons.arrow_forward : Icons.restore,
                                            size: 16,
                                            color: widget.isPending ? Colors.blue[700] : customRed,
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            if (status == 'rejected' && data['rejectionReason'] != null)
                              Container(
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.all(10),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: customRed.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: customRed.withOpacity(0.2)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 14, color: customRed),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "Reason: ${data['rejectionReason']}",
                                        style: TextStyle(
                                          color: customRed,
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showRevertDialog(BuildContext context, String docId, String currentStatus) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Revert Payment?"),
        content: Text("This payment is marked as ${currentStatus.toUpperCase()}. Do you want to revert it back to Pending status?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: customRed)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: customRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await FeeService().revertPayment(docId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Payment Reverted to Pending")),
                );
              }
            },
            child: const Text("Revert to Pending"),
          )
        ],
      ),
    );
  }
}