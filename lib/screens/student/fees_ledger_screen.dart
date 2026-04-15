import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class FeesLedgerScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const FeesLedgerScreen({super.key, required this.userData});

  @override
  State<FeesLedgerScreen> createState() => _FeesLedgerScreenState();
}

class _FeesLedgerScreenState extends State<FeesLedgerScreen> {
  final User _user = FirebaseAuth.instance.currentUser!;
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

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
          'Financial Ledger',
          style: TextStyle(color: customRed, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('payments')
            .where('studentId', isEqualTo: _user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          
          double totalPaid = 0;
          double totalPendingVerification = 0;

          // Process transactions and sort by date descending
          List<Map<String, dynamic>> transactions = [];
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] ?? 'unknown';
            final amt = (data['amountPaid'] as num?)?.toDouble() ?? (data['amount'] as num?)?.toDouble() ?? 0.0;
            
            if (status == 'verified') {
              totalPaid += amt;
            } else if (status == 'pending' || status == 'under_review') {
              totalPendingVerification += amt;
            }
            
            transactions.add({
              'id': doc.id,
              ...data,
            });
          }

          // Sort by submittedAt if available
          transactions.sort((a, b) {
            Timestamp? tA = a['submittedAt'] as Timestamp?;
            Timestamp? tB = b['submittedAt'] as Timestamp?;
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tB.compareTo(tA); // Descending
          });

          return Column(
            children: [
              _buildLedgerSummary(totalPaid, totalPendingVerification),
              
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, color: Colors.grey[800], size: 20),
                    const SizedBox(width: 8),
                    Text('Transaction History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                  ],
                ),
              ),

              Expanded(
                child: transactions.isEmpty 
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: transactions.length,
                      itemBuilder: (context, index) {
                        return _buildTransactionCard(transactions[index]);
                      },
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLedgerSummary(double totalPaid, double pendingVerify) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: customRed.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL VERIFIED PAYMENTS", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              Icon(Icons.account_balance_wallet_rounded, color: customRed.withOpacity(0.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text("₹${totalPaid.toStringAsFixed(0)}", style: const TextStyle(color: Colors.black87, fontSize: 36, fontWeight: FontWeight.bold)),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Pending Verification", style: TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text("₹${pendingVerify.toStringAsFixed(0)}", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("Report Discrepancy", style: TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text("Raise Support Ticket", style: TextStyle(color: Colors.blue[600], fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline)),
                ],
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final status = tx['status'] ?? 'unknown';
    final amt = (tx['amountPaid'] as num?)?.toDouble() ?? (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final feeType = tx['feeType'] ?? tx['id'].split('_').last ?? 'Fee';
    final semester = tx['semester'] ?? 'N/A';
    
    String dateStr = '—';
    if (tx['submittedAt'] != null) {
      dateStr = DateFormat('dd MMM yyyy, hh:mm a').format((tx['submittedAt'] as Timestamp).toDate());
    }

    Color sColor = Colors.grey;
    IconData sIcon = Icons.help_outline_rounded;
    if (status == 'verified') { sColor = Colors.green; sIcon = Icons.check_circle_rounded; }
    else if (status == 'under_review' || status == 'pending') { sColor = Colors.orange; sIcon = Icons.hourglass_top_rounded; }
    else if (status == 'rejected') { sColor = customRed; sIcon = Icons.error_outline_rounded; }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: sColor.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(sIcon, color: sColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(feeType.toString().replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text("Semester $semester", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("₹${amt.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(status.toUpperCase(), style: TextStyle(color: sColor, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dateStr, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                if (status == 'verified')
                  TextButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Receipt download coming soon'), backgroundColor: customRed));
                    },
                    icon: Icon(Icons.download_rounded, size: 14, color: customRed),
                    label: Text("Receipt", style: TextStyle(color: customRed, fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No Transactions Yet", style: TextStyle(color: Colors.grey[600], fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
