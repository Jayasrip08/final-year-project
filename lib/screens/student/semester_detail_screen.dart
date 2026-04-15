import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:confetti/confetti.dart';
import 'package:uuid/uuid.dart';
import '../../services/fee_service.dart';
import 'package:intl/intl.dart';
import 'payment_screen.dart';

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
  final Map<String, double> _feeComponents = {};
  final Map<String, Map<String, dynamic>> _paymentStatus = {};

  DateTime? _deadline;
  DateTime? _examDeadline;
  final User _user = FirebaseAuth.instance.currentUser!;

  // CUSTOM PROJECT COLOR
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  // No-Due Certificate State
  Map<String, dynamic>? _noDueCertData;
  bool _isNoDueLoading = true;
  bool _isGeneratingCert = false;

  // Confetti
  late ConfettiController _confettiController;

  // Flag to prevent multiple dialogs
  bool _hasShownClearDialog = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _loadDetails();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      String dept = widget.userData['dept'] ?? 'CSE';
      String quota = widget.userData['quotaCategory'] ?? 'Management';
      String batch = widget.userData['batch'] ?? '2024-2028';
      String studentType = widget.userData['studentType'] ?? 'day_scholar';
      String? busPlace = widget.userData['busPlace'];

      // Clear existing data before reloading
      _feeComponents.clear();
      _paymentStatus.clear();

      debugPrint("DEBUG: Loading for $dept, $quota, $batch, Semester ${widget.semester}");

      var structure = await FeeService().getFeeComponents(dept, quota, batch, widget.semester);
      
      if (structure != null) {
        debugPrint("DEBUG: Structure found: ${structure.toString()}");
        
        // Use safe casting for Timestamps
        if (structure['deadline'] != null && structure['deadline'] is Timestamp) {
          _deadline = (structure['deadline'] as Timestamp).toDate();
        }
        if (structure['examDeadline'] != null && structure['examDeadline'] is Timestamp) {
          _examDeadline = (structure['examDeadline'] as Timestamp).toDate();
        }

        if (structure['examFee'] != null && (structure['examFee'] as num) > 0) {
           _feeComponents['Exam Fee'] = (structure['examFee'] as num).toDouble();
        }

        Map<String, dynamic> rawComponents = structure['components'] ?? {};
        
        for (var entry in rawComponents.entries) {
          String feeType = entry.key;
          var feeValue = entry.value;

          // Logic filters
          if (feeType.toLowerCase().contains('hostel') && studentType != 'hosteller') continue;
          
          if (feeType.toLowerCase().contains('bus')) {
            if (studentType != 'bus_user') continue;
            else if (feeValue is Map) {
              if (busPlace != null && feeValue.containsKey(busPlace)) {
                _feeComponents[feeType] = (feeValue[busPlace] as num).toDouble();
              }
              continue;
            }
          }
          if (feeValue is num) _feeComponents[feeType] = feeValue.toDouble();
        }
      } else {
        debugPrint("DEBUG: No fee structure returned from FeeService");
      }

      // Fetch Payments — wrapped per fee-type so one failure doesn't abort all
      for (String feeType in _feeComponents.keys) {
        String sanitizedType = feeType.replaceAll(" ", "_");
        String paymentId1 = "${_user.uid}_${widget.semester}_$sanitizedType";
        String paymentId2 = "${paymentId1}_inst2";
        
        try {
          var doc1 = await FirebaseFirestore.instance.collection('payments').doc(paymentId1).get();
          var doc2 = await FirebaseFirestore.instance.collection('payments').doc(paymentId2).get();
          
          if (doc2.exists) {
            var d1 = doc1.exists ? doc1.data() as Map<String, dynamic> : null;
            var d2 = doc2.data() as Map<String, dynamic>;
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
        } catch (e) {
          // Default to not_paid if we can't read this payment doc
          debugPrint("DEBUG: Payment fetch failed for $feeType: $e");
          _paymentStatus[feeType] = {'status': 'not_paid'};
        }
      }

      // Fetch No-Due Certificate status
      try {
        final certDoc = await FirebaseFirestore.instance
            .collection('no_due_certificates')
            .doc('${_user.uid}_${widget.semester}')
            .get();
        _noDueCertData = certDoc.exists ? certDoc.data() : null;
      } catch (e) {
        debugPrint("DEBUG: No-due cert fetch failed: $e");
        _noDueCertData = null;
      }

      // Check Eligibility
      double totalMandatoryExpected = 0;
      double totalMandatoryPaid = 0;
      _feeComponents.forEach((key, expectedAmt) {
        if (key != 'Exam Fee') {
          totalMandatoryExpected += expectedAmt;
          var payment = _paymentStatus[key];
          if (payment?['status'] == 'verified' || payment?['status'] == 'partially_paid') {
            totalMandatoryPaid += (payment?['amountPaid'] as num?)?.toDouble() ?? (payment?['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
      });
      
      bool isEligibleForNoDue = totalMandatoryPaid >= totalMandatoryExpected && _feeComponents.isNotEmpty;

      if (isEligibleForNoDue && mounted) {
        // Only show dialog once
        if (!_hasShownClearDialog) {
          _hasShownClearDialog = true;
          // Delay so widget is fully built before triggering confetti + dialog
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _confettiController.play();
            }
          });
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (mounted) {
              _showFeeClearedDialog();
            }
          });
        }
      } else {
        _hasShownClearDialog = false;
      }
    } catch (e) {
      debugPrint("DEBUG ERROR: SemesterDetailScreen _loadDetails failed: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isNoDueLoading = false;
        });
      }
    }
  }

  Future<void> _uploadBill(String feeType, double amount) async {
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
    _loadDetails();
  }

  Future<void> _generateCertificate({bool isReissue = false}) async {
    setState(() => _isGeneratingCert = true);
    try {
      final existingCertId = _noDueCertData?['certId'] as String?;
      final certId = existingCertId ?? const Uuid().v4();

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
        await certRef.update({
          'status': 'issued',
          'generatedCount': FieldValue.increment(1),
          'reissueApprovedAt': null,
        });
      }

      await _loadDetails();

      // Tell the student where to download the certificate
      if (mounted) _showCertReadyDialog();
    } catch (e) {
      debugPrint("Error generating cert: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to issue certificate. Please try again.'),
            backgroundColor: customRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingCert = false);
    }
  }

  void _showCertReadyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_rounded, color: Colors.green, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('Certificate Ready!'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your No-Due Certificate has been issued successfully.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Go to Dashboard → Documents to download your certificate as a PDF.',
                    style: TextStyle(fontSize: 13, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: customRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showFeeClearedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.celebration, color: customRed),
            const SizedBox(width: 8),
            const Text('Congratulations!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You have cleared all mandatory fees for this semester.'),
            const SizedBox(height: 16),
            const Text('You can now generate your No-Due Certificate.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Later', style: TextStyle(color: customRed)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _generateCertificate();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: customRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Generate Certificate'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDueCertButton() {
    if (_isNoDueLoading) {
      return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
    }

    final certStatus = _noDueCertData?['status'];

    if (certStatus == null) {
      return ElevatedButton(
        onPressed: () => _generateCertificate(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: customRed,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: const Text("GENERATE NO-DUE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      );
    }

    if (certStatus == 'issued') {
      final int generatedCount = (_noDueCertData?['generatedCount'] ?? 1) as int;
      final bool maxReissuesReached = generatedCount >= 3;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 16),
              SizedBox(width: 4),
              Text("Digital Certificate Issued", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          if (!maxReissuesReached)
            TextButton(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('no_due_certificates')
                    .doc('${_user.uid}_${widget.semester}')
                    .update({'status': 'reissue_requested', 'reissueRequestedAt': FieldValue.serverTimestamp()});
                _loadDetails();
              },
              child: const Text("Request Reissue", style: TextStyle(color: Colors.white70, fontSize: 12, decoration: TextDecoration.underline)),
            ),
        ],
      );
    }

    if (certStatus == 'reissue_requested') {
      return const Text("Reissue Pending Approval", style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold));
    }

    if (certStatus == 'reissue_approved') {
      return ElevatedButton(
        onPressed: () => _generateCertificate(isReissue: true),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.greenAccent,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text("REISSUE CERTIFICATE"),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Semester ${widget.semester}", style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: customRed,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Main content (always in tree)
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            RefreshIndicator(
              onRefresh: _loadDetails,
              color: customRed,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 30),
                  const Text("Detailed Fee Breakdown", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 16),
                  if (_feeComponents.isEmpty)
                     _buildEmptyFees()
                  else
                    ..._feeComponents.entries.map((entry) => _buildFeeItem(entry.key, entry.value)),
                ],
              ),
            ),
          // Confetti overlay — always in the widget tree so it can animate at any time
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [Colors.green, Colors.yellow, Colors.red, Colors.blue, Colors.orange],
              numberOfParticles: 50,
              gravity: 0.15,
              strokeWidth: 1.5,
              emissionFrequency: 0.05,
              maximumSize: const Size(20, 10),
              minimumSize: const Size(8, 4),
            ),
          ),
          if (!_isLoading && _isGeneratingCert) _buildProcessingOverlay(),
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
    bool mainFeesOverdue = _deadline != null && DateTime.now().isAfter(_deadline!) && 
        _feeComponents.entries.any((e) => e.key != 'Exam Fee' && (_paymentStatus[e.key]?['status'] ?? 'not_paid') != 'verified');

    Map<String, double> mandatoryFees = Map.from(_feeComponents)..remove('Exam Fee');
    double totalMandatoryExpected = mandatoryFees.values.fold(0, (s, v) => s + v);
    double totalMandatoryPaid = 0.0;
    mandatoryFees.forEach((key, expectedAmt) {
      var payment = _paymentStatus[key];
      if (payment?['status'] == 'verified' || payment?['status'] == 'partially_paid') {
        totalMandatoryPaid += (payment?['amountPaid'] as num?)?.toDouble() ?? (payment?['amount'] as num?)?.toDouble() ?? 0.0;
      }
    });

    bool isEligibleForNoDue = totalMandatoryPaid >= totalMandatoryExpected && totalCount > 0;

    final Gradient gradient;
    if (isEligibleForNoDue) {
      gradient = LinearGradient(
        colors: [Colors.green.shade700, Colors.green.shade400],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else {
      gradient = LinearGradient(
        colors: [customRed, customRed.withOpacity(0.85)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isEligibleForNoDue ? Colors.green.withOpacity(0.3) : customRed.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("TOTAL SEMESTER FEE", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text("₹${total.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          if (isEligibleForNoDue)
            _buildClearedMessage()
          else if (_deadline != null)
            _buildDeadlineRow(mainFeesOverdue),
          const Divider(color: Colors.white24, height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("CLEARED", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text("$paidCount / $totalCount Items", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              if (isEligibleForNoDue) _buildNoDueCertButton()
            ],
          )
        ],
      ),
    );
  }

  Widget _buildClearedMessage() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.celebration_rounded, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            "ALL FEES CLEARED 🎉",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlineRow(bool isOverdue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isOverdue ? Icons.warning_amber_rounded : Icons.calendar_today_rounded, color: isOverdue ? Colors.orangeAccent : Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            isOverdue ? "OVERDUE: ${DateFormat('dd MMM').format(_deadline!)}" : "DUE DATE: ${DateFormat('dd MMM').format(_deadline!)}",
            style: TextStyle(color: isOverdue ? Colors.orangeAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeItem(String title, double amount) {
    var statusData = _paymentStatus[title] ?? {'status': 'not_paid'};
    String status = statusData['status'];
    if (status == 'verified' && ((statusData['amountPaid'] as num?)?.toDouble() ?? (statusData['amount'] as num?)?.toDouble() ?? 0.0) < amount) {
      status = 'partially_paid';
    }

    Color statusColor = Colors.grey;
    IconData icon = Icons.radio_button_unchecked_rounded;
    String statusText = "Not Paid";

    if (status == 'under_review') { statusColor = Colors.orange; icon = Icons.hourglass_top_rounded; statusText = "Pending Verification"; }
    else if (status == 'verified') { statusColor = Colors.green; icon = Icons.check_circle_rounded; statusText = "Verified"; }
    else if (status == 'rejected') { statusColor = customRed; icon = Icons.error_outline_rounded; statusText = "Rejected"; }
    else if (status == 'partially_paid') { statusColor = Colors.blue; icon = Icons.pie_chart_rounded; statusText = "Partially Paid"; }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: statusColor.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: statusColor, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(status == 'partially_paid' ? "Paid: ₹${statusData['amountPaid']} / Total: ₹$amount" : "Amount: ₹$amount", 
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        trailing: (status == 'not_paid' || status == 'rejected' || status == 'partially_paid')
          ? _buildPayButton(title, amount, status == 'partially_paid') : null,
      ),
    );
  }

  Widget _buildPayButton(String title, double amount, bool isPartial) {
    return ElevatedButton(
      onPressed: () => _uploadBill(title, amount),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPartial ? Colors.blue : customRed,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: Text(isPartial ? "BALANCE" : "PAY", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: customRed),
                const SizedBox(height: 20),
                const Text("Securing Digital Certificate...", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyFees() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.receipt_long_outlined, size: 60, color: Colors.grey[200]),
          const SizedBox(height: 16),
          const Text("No fee data found", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}