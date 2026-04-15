import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/fee_service.dart';

class FeesLedgerScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const FeesLedgerScreen({super.key, required this.userData});

  @override
  State<FeesLedgerScreen> createState() => _FeesLedgerScreenState();
}

class _FeesLedgerScreenState extends State<FeesLedgerScreen> {
  final User _user = FirebaseAuth.instance.currentUser!;
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  Future<Map<String, double>> _calculateOverallTotals() async {
    double totalExpected = 0;
    final String dept = widget.userData['dept'] ?? '';
    final String quota = widget.userData['quotaCategory'] ?? '';
    final String batch = widget.userData['batch'] ?? '';
    final String studentType = widget.userData['studentType'] ?? 'day_scholar';

    // 1. Calculate Expected Fee for all 8 Semesters
    for (int i = 1; i <= 8; i++) {
       final structure = await FeeService().getFeeComponents(dept, quota, batch, "Semester $i");
       if (structure != null) {
          // Add Exam Fee
          totalExpected += (structure['examFee'] as num?)?.toDouble() ?? 0.0;
          
          // Add Components
          Map<String, dynamic> components = structure['components'] ?? {};
          for (var entry in components.entries) {
            String type = entry.key;
            var val = entry.value;
            
            // Skip hostel if not hosteller
            if (type.toLowerCase().contains('hostel') && studentType != 'hosteller') continue;
            // Skip bus if not bus user
            if (type.toLowerCase().contains('bus') && studentType != 'bus_user') continue;

            if (val is num) totalExpected += val.toDouble();
            else if (val is Map) {
              String? busPlace = widget.userData['busPlace'];
              if (busPlace != null && val.containsKey(busPlace)) {
                totalExpected += (val[busPlace] as num).toDouble();
              }
            }
          }
       }
    }

    // 2. Fetch Wallet Balance
    double walletBalance = 0;
    try {
      final wDoc = await FirebaseFirestore.instance.collection('wallets').doc(_user.uid).get();
      if (wDoc.exists) {
        walletBalance = (wDoc.data()?['balance'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}

    return {
      'totalExpected': totalExpected,
      'walletBalance': walletBalance,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, double>>(
      future: _calculateOverallTotals(),
      builder: (context, totalsSnapshot) {
        return Scaffold(
          backgroundColor: const Color(0xFFF7F8FC),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
            iconTheme: IconThemeData(color: customRed),
            title: Text(
              'Degree Ledger',
              style: TextStyle(color: customRed, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('payments')
                .where('studentId', isEqualTo: _user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting || !totalsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              double totalPaid = 0;
              double totalPendingVerification = 0;

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
                
                transactions.add({'id': doc.id, ...data});
              }

              transactions.sort((a, b) {
                Timestamp? tA = a['submittedAt'] as Timestamp?;
                Timestamp? tB = b['submittedAt'] as Timestamp?;
                if (tA == null && tB == null) return 0;
                if (tA == null) return 1;
                if (tB == null) return -1;
                return tB.compareTo(tA);
              });

              final expected = totalsSnapshot.data!['totalExpected'] ?? 0.0;
              final wallet = totalsSnapshot.data!['walletBalance'] ?? 0.0;
              final outstanding = expected - (totalPaid + wallet);

              return Column(
                children: [
                  _buildLedgerSummary(totalPaid, totalPendingVerification, expected, outstanding, wallet),
                  
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded, color: Colors.grey[800], size: 20),
                        const SizedBox(width: 8),
                        Text('Full Payment History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[800])),
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
    );
  }

  Widget _buildLedgerSummary(double verified, double pending, double totalDegree, double outstanding, double wallet) {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        children: [
          // Primary Section
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [customRed, customRed.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("DEGREE FINANCIAL SUMMARY", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    Icon(Icons.verified_user_rounded, color: Colors.white.withOpacity(0.5), size: 20),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Outstanding Balance", style: TextStyle(color: Colors.white, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text("₹${outstanding.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    _summaryBadge("Verified", "₹${verified.toStringAsFixed(0)}"),
                  ],
                ),
              ],
            ),
          ),
          // Secondary Section
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _ledgerRow("Total Course Fee (8 Sems)", "₹${totalDegree.toStringAsFixed(0)}"),
                const SizedBox(height: 12),
                _ledgerRow("Wallet Credit Available", "₹${wallet.toStringAsFixed(0)}", isHighlight: true),
                const SizedBox(height: 12),
                _ledgerRow("Pending Verification", "₹${pending.toStringAsFixed(0)}", color: Colors.orange.shade700),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _ledgerRow(String label, String value, {Color? color, bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal)),
        Text(value, style: TextStyle(color: color ?? (isHighlight ? Colors.teal : Colors.black87), fontSize: 14, fontWeight: FontWeight.bold)),
      ],
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
