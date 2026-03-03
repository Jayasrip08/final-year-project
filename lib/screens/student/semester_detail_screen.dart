import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/fee_service.dart';
import '../../services/pdf_service.dart';
import 'package:intl/intl.dart';
import 'payment_screen.dart';
// import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'; // Uncomment when ready

class SemesterDetailScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String semester;

  const SemesterDetailScreen({
    super.key,
    required this.userData,
    required this.semester,
  });

  @override
  State<SemesterDetailScreen> createState() => _SemesterDetailScreenState();
}

class _SemesterDetailScreenState extends State<SemesterDetailScreen> {
  bool _isLoading = true;
  Map<String, double> _feeComponents = {};
  Map<String, Map<String, dynamic>> _paymentStatus = {};

  DateTime? _deadline;
  DateTime? _examDeadline;
  final User _user = FirebaseAuth.instance.currentUser!;

  // No-Due Certificate State
  Map<String, dynamic>? _noDueCertData;
  bool _isNoDueLoading = true;
  bool _isGeneratingCert = false; // Add this for busy state

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);

    String dept = widget.userData['dept'] ?? 'CSE';
    String quota = widget.userData['quotaCategory'] ?? 'Management';
    String batch = widget.userData['batch'] ?? '2024-2028';
    String studentType = widget.userData['studentType'] ?? 'day_scholar';
    String? busPlace = widget.userData['busPlace'];

    // 1. Fetch Fee Structure
    var structure = await FeeService().getFeeComponents(dept, quota, batch, widget.semester);
    
    if (structure != null) {
      if (structure['deadline'] != null) {
        _deadline = (structure['deadline'] as Timestamp?)?.toDate();
      }
      if (structure['examDeadline'] != null) {
        _examDeadline = (structure['examDeadline'] as Timestamp?)?.toDate();
      }

      // Add Exam Fee if exists
      if (structure['examFee'] != null && (structure['examFee'] as num) > 0) {
         _feeComponents['Exam Fee'] = (structure['examFee'] as num).toDouble();
      }

      Map<String, dynamic> rawComponents = structure['components'] ?? {};
      
      // Filter fees based on student type
      for (var entry in rawComponents.entries) {
        String feeType = entry.key;
        var feeValue = entry.value;
        
        // Skip hostel fee for non-hostellers
        if (feeType.toLowerCase().contains('hostel') && studentType != 'hosteller') {
          continue;
        }
        
        // Handle bus fee
        if (feeType.toLowerCase().contains('bus')) {
          if (studentType != 'bus_user') {
            continue; // Skip bus fee for non-bus users
          } else if (feeValue is Map) {
            // Bus fee is a map of places, get only the student's place
            if (busPlace != null && feeValue.containsKey(busPlace)) {
              _feeComponents[feeType] = (feeValue[busPlace] as num).toDouble();
            }
            continue;
          }
        }
        
        // Add other fees
        if (feeValue is num) {
          _feeComponents[feeType] = feeValue.toDouble();
        }
      }
    }

    // 2. Fetch Payments for each component
    for (String feeType in _feeComponents.keys) {
      String sanitizedType = feeType.replaceAll(" ", "_");
      String paymentId1 = "${_user.uid}_${widget.semester}_$sanitizedType";
      String paymentId2 = "${_user.uid}_${widget.semester}_$sanitizedType" + "_inst2";
      
      var doc1 = await FirebaseFirestore.instance.collection('payments').doc(paymentId1).get();
      var doc2 = await FirebaseFirestore.instance.collection('payments').doc(paymentId2).get();
      
      if (doc2.exists) {
        // If inst2 exists, it takes precedence for status, but we may want to combine them
        var d1 = doc1.exists ? doc1.data() as Map<String, dynamic> : null;
        var d2 = doc2.data() as Map<String, dynamic>;
        
        // If both are verified, status is verified
        if (d1 != null && d1['status'] == 'verified' && d2['status'] == 'verified') {
           double p1 = (d1['amountPaid'] as num?)?.toDouble() ?? (d1['amount'] as num?)?.toDouble() ?? 0.0;
           double p2 = (d2['amountPaid'] as num?)?.toDouble() ?? (d2['amount'] as num?)?.toDouble() ?? 0.0;
           _paymentStatus[feeType] = {...d2, 'amountPaid': p1 + p2};
        } else if ((d1 != null && d1['status'] == 'rejected') || d2['status'] == 'rejected') {
           _paymentStatus[feeType] = (d1 != null && d1['status'] == 'rejected') ? d1 : d2;
        } else {
           _paymentStatus[feeType] = {'status': 'under_review', 'isPartial': true};
        }
      } else if (doc1.exists) {
        var data = doc1.data() as Map<String, dynamic>;
        if (data['isInstallment'] == true && data['status'] == 'verified') {
           _paymentStatus[feeType] = {...data, 'status': 'partially_paid'};
        } else {
           _paymentStatus[feeType] = data;
        }
      } else {
        _paymentStatus[feeType] = {'status': 'not_paid'};
      }
    }

    // 3. Load No-Due Certificate record
    final certDoc = await FirebaseFirestore.instance
        .collection('no_due_certificates')
        .doc('${_user.uid}_${widget.semester}')
        .get();
    _noDueCertData = certDoc.exists ? certDoc.data() : null;

    if (mounted) setState(() {
      _isLoading = false;
      _isNoDueLoading = false;
    });
  }

  Future<void> _uploadBill(String feeType, double amount) async {
    // Navigate to PaymentScreen for the full payment flow
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          feeType: feeType,
          amount: amount,
          semester: widget.semester,
        ),
      ),
    );
    _loadDetails(); // Refresh details on return
  }

  Future<void> _generateCertificate({bool isReissue = false}) async {
    setState(() => _isGeneratingCert = true);
    try {
      Map<String, double> paidFees = {};
    _feeComponents.forEach((feeType, amount) {
      if (_paymentStatus[feeType]?['status'] == 'verified') {
        paidFees[feeType] = amount;
      }
    });

    // Reuse existing certId on reissue so the QR keeps working
    final existingCertId = _noDueCertData?['certId'] as String?;

    final certId = await PdfService().generateAndDownloadCertificate(
      widget.userData['name'] ?? 'Student',
      widget.userData['regNo'] ?? '',
      widget.userData['dept'] ?? 'CSE',
      widget.userData['batch'] ?? '',
      widget.semester,
      paidFees,
      certId: existingCertId, // null on first gen → UUID created inside
    );

    // Write/update Firestore record
    final certRef = FirebaseFirestore.instance
        .collection('no_due_certificates')
        .doc('${_user.uid}_${widget.semester}');

    if (!isReissue) {
      await certRef.set({
        'uid': _user.uid,
        'semester': widget.semester,
        'generatedAt': FieldValue.serverTimestamp(),
        'generatedCount': 1,
        'status': 'issued',
        'certId': certId,
        'verifyUrl': 'https://a-dacs.web.app/verify?id=$certId',
        'studentName': widget.userData['name'] ?? '',
        'regNo': widget.userData['regNo'] ?? '',
        'dept': widget.userData['dept'] ?? '',
        'batch': widget.userData['batch'] ?? '',
      });
    } else {
      // Reissue approved — increment count and set back to issued
      await certRef.update({
        'status': 'issued',
        'generatedCount': FieldValue.increment(1),
        'reissueApprovedAt': null,
      });
    }
    _loadDetails();
    } catch (e) {
      debugPrint("Error generating cert: $e");
    } finally {
      if (mounted) setState(() => _isGeneratingCert = false);
    }
  }

  Widget _buildNoDueCertButton() {
    if (_isNoDueLoading) {
      return const SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }

    final certStatus = _noDueCertData?['status'];

    if (certStatus == null) {
      // Never generated — show download button
      return ElevatedButton.icon(
        onPressed: () => _generateCertificate(),
        icon: const Icon(Icons.download, size: 16, color: Colors.indigo),
        label: const Text("NO DUE CERT", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
      );
    }

    if (certStatus == 'issued') {
      final int generatedCount = (_noDueCertData?['generatedCount'] ?? 1) as int;
      final bool maxReissuesReached = generatedCount >= 3; // 1 original + 2 reissues

      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified, color: Colors.greenAccent, size: 16),
              SizedBox(width: 4),
              Text("No-Due Issued", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          if (maxReissuesReached)
            const Text("Max reissues reached", style: TextStyle(color: Colors.white54, fontSize: 11))
          else
            OutlinedButton.icon(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('no_due_certificates')
                    .doc('${_user.uid}_${widget.semester}')
                    .update({
                  'status': 'reissue_requested',
                  'reissueRequestedAt': FieldValue.serverTimestamp(),
                });
                _loadDetails();
              },
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text("Request Reissue", style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
        ],
      );
    }

    if (certStatus == 'reissue_requested') {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_top, color: Colors.orangeAccent, size: 16),
          SizedBox(width: 4),
          Text("Reissue Pending Approval", style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      );
    }

    if (certStatus == 'reissue_approved') {
      return ElevatedButton.icon(
        onPressed: () => _generateCertificate(isReissue: true),
        icon: const Icon(Icons.download, size: 16, color: Colors.indigo),
        label: const Text("Download Again", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Semester ${widget.semester} - Fee Details")),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _loadDetails,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildSummaryCard(),
                      const SizedBox(height: 20),
                      const Text("Fee Components", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      if (_feeComponents.isEmpty)
                         Padding(
                           padding: const EdgeInsets.all(20),
                           child: Column(
                             children: [
                               const Text("No fees configured for this semester yet.", style: TextStyle(fontStyle: FontStyle.italic)),
                               const SizedBox(height: 10),
                               Text(
                                 "Your Profile: ${widget.userData['dept']} | ${widget.userData['quotaCategory']} | ${widget.userData['batch']}",
                                 style: TextStyle(fontSize: 12, color: Colors.indigo[300]),
                               ),
                             ],
                           ),
                         )
                      else
                        ..._feeComponents.entries.map((entry) => _buildFeeItem(entry.key, entry.value)),
                    ],
                  ),
                ),
                if (_isGeneratingCert)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text("Generating Secure Certificate...", style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildSummaryCard() {
    double total = _feeComponents.values.fold(0, (sum, val) => sum + val);
    
    int paidCount = 0;
    _feeComponents.forEach((key, expectedAmt) {
      var payment = _paymentStatus[key];
      if (payment?['status'] == 'verified' || payment?['status'] == 'partially_paid') {
          double paid = (payment?['amountPaid'] as num?)?.toDouble() ?? (payment?['amount'] as num?)?.toDouble() ?? 0.0;
          if (paid >= expectedAmt) paidCount++;
      }
    });
    
    int totalCount = _feeComponents.length;
    
    // Check main fees overdue status
    bool mainFeesOverdue = false;
    if (_deadline != null && DateTime.now().isAfter(_deadline!)) {
      // Check if any non-exam fee is unpaid
      bool anyMainFeeUnpaid = false;
      _feeComponents.forEach((key, val) {
        if (key != 'Exam Fee') { // Skip Exam Fee for main deadline check
           var status = _paymentStatus[key]?['status'] ?? 'not_paid';
           if (status != 'verified') anyMainFeeUnpaid = true;
        }
      });
      if (anyMainFeeUnpaid) mainFeesOverdue = true;
    }

    // Check exam fee overdue status
    bool examFeeOverdue = false;
    if (_examDeadline != null && _feeComponents.containsKey('Exam Fee') && DateTime.now().isAfter(_examDeadline!)) {
       var status = _paymentStatus['Exam Fee']?['status'] ?? 'not_paid';
       if (status != 'verified') examFeeOverdue = true;
    }

    // Exclude 'Exam Fee' from No Due calculation
    Map<String, double> mandatoryFees = Map.from(_feeComponents);
    mandatoryFees.remove('Exam Fee');

    double totalMandatoryExpected = 0.0;
    double totalMandatoryPaid = 0.0;
    
    mandatoryFees.forEach((key, expectedAmt) {
      totalMandatoryExpected += expectedAmt;
      var payment = _paymentStatus[key];
      if (payment?['status'] == 'verified') {
        // Use amountPaid from payment doc, fallback to 0 if not present
        totalMandatoryPaid += (payment?['amountPaid'] as num?)?.toDouble() ?? (payment?['amount'] as num?)?.toDouble() ?? 0.0;
      } else if (payment?['status'] == 'partially_paid') {
          totalMandatoryPaid += (payment?['amountPaid'] as num?)?.toDouble() ?? (payment?['amount'] as num?)?.toDouble() ?? 0.0;
      }
    });

    // Eligible ONLY if the total verified amount paid covers the total expected mandatory fees
    bool isEligibleForNoDue = totalMandatoryPaid >= totalMandatoryExpected && totalCount > 0;

    bool isFullyPaid = paidCount == totalCount && totalCount > 0;
    bool isOverdue = !isFullyPaid && (mainFeesOverdue || examFeeOverdue);

    Color cardColor = isOverdue ? Colors.red.shade700 : Colors.indigo;

    return Card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("Total Semester Fee", style: TextStyle(color: Colors.white70)),
            Text("₹ $total", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            
            // MAIN DEADLINE
            if (_deadline != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      mainFeesOverdue ? Icons.error_outline : Icons.calendar_today, 
                      color: Colors.white, 
                      size: 16
                    ),
                    const SizedBox(width: 8),
                    Text(
                      mainFeesOverdue 
                        ? "Fees Overdue! Due: ${DateFormat('dd MMM yyyy').format(_deadline!)}"
                        : "Fees Due: ${DateFormat('dd MMM yyyy').format(_deadline!)}",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

             // EXAM DEADLINE (Show if different from main deadline)
             if (_examDeadline != null && _feeComponents.containsKey('Exam Fee'))
               Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      examFeeOverdue ? Icons.assignment_late : Icons.assignment, 
                      color: Colors.white70, 
                      size: 16
                    ),
                    const SizedBox(width: 8),
                    Text(
                      examFeeOverdue 
                        ? "Exam Fee Overdue! Due: ${DateFormat('dd MMM yyyy').format(_examDeadline!)}"
                        : "Exam Fee Due: ${DateFormat('dd MMM yyyy').format(_examDeadline!)}",
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            const Divider(color: Colors.white24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Progress: $paidCount / $totalCount Paid", style: const TextStyle(color: Colors.white)),
                if (isEligibleForNoDue)
                  _buildNoDueCertButton()
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildFeeItem(String title, double amount) {
    var statusData = _paymentStatus[title] ?? {'status': 'not_paid'};
    String rawStatus = statusData['status'];
    String status = rawStatus;
    
    // Override logic: if verified but paid < expected, it's actually partially paid
    if (rawStatus == 'verified') {
      double paid = (statusData['amountPaid'] as num?)?.toDouble() ?? (statusData['amount'] as num?)?.toDouble() ?? 0.0;
      if (paid < amount) {
        status = 'partially_paid';
      }
    }

    Color color = Colors.grey;
    IconData icon = Icons.circle_outlined;
    String statusText = "Not Paid";

    if (status == 'under_review') {
      color = Colors.orange;
      icon = Icons.hourglass_empty;
      statusText = "Verification Pending";
    } else if (status == 'verified') {
      color = Colors.green;
      icon = Icons.check_circle;
      statusText = "Verified";
    } else if (status == 'rejected') {
      color = Colors.red;
      icon = Icons.error_outline;
      statusText = "Rejected";
    } else if (status == 'partially_paid') {
      color = Colors.blue;
      icon = Icons.pie_chart;
      statusText = "Partially Paid";
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (status == 'partially_paid') 
               Text("Paid: ₹ ${statusData['amountPaid'] ?? statusData['amount']} / Total: ₹ $amount")
            else
               Text("Amount: ₹ $amount"),
            Text(statusText, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
            if (status == 'rejected' && statusData['rejectionReason'] != null)
              Text("Reason: ${statusData['rejectionReason']}", style: const TextStyle(color: Colors.red, fontSize: 11)),
          ],
        ),
        trailing: status == 'not_paid' || status == 'rejected' || status == 'partially_paid'
          ? ElevatedButton.icon(
              icon: Icon(status == 'partially_paid' ? Icons.add : Icons.upload_file, size: 16),
              label: Text(status == 'partially_paid' ? "Pay or Upload Balance" : "Pay or Upload Receipt"),
              onPressed: () => _uploadBill(title, amount),
              style: ElevatedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: status == 'partially_paid' ? Colors.blue : null,
                foregroundColor: status == 'partially_paid' ? Colors.white : null,
              ),
            )
          : null,
      ),
    );
  }
}
