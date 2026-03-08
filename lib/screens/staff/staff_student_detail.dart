import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/fee_service.dart';
import '../../services/pdf_service.dart';

class StaffStudentDetail extends StatefulWidget {
  final Map<String, dynamic> studentData;
  final String studentId;

  const StaffStudentDetail({super.key, required this.studentData, required this.studentId});

  @override
  State<StaffStudentDetail> createState() => _StaffStudentDetailState();
}

class _StaffStudentDetailState extends State<StaffStudentDetail> {
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);
  final Color customGreen = Colors.green.shade700;

  String _selectedSemester = '';
  List<String> _availableSemesters = [];
  bool _isLoadingSemesters = true;

  @override
  void initState() {
    super.initState();
    _loadSemestersForStudent();
  }

  Future<void> _loadSemestersForStudent() async {
    final sBatch = (widget.studentData['batch'] ?? '').toString().toLowerCase();
    if (sBatch.isEmpty) return;

    try {
      final yearsSnapshot = await FirebaseFirestore.instance
          .collection('academic_years')
          .where('isActive', isEqualTo: true)
          .get();

      String? matchedYearId;
      for (var doc in yearsSnapshot.docs) {
        final yName = doc['name'].toString().toLowerCase();
        if (yName == sBatch) {
          matchedYearId = doc.id;
          break;
        }
      }
      if (matchedYearId == null) {
        for (var doc in yearsSnapshot.docs) {
          final yName = doc['name'].toString().toLowerCase();
          if (yName.contains(sBatch) || sBatch.contains(yName)) {
            matchedYearId = doc.id;
            break;
          }
        }
      }

      if (matchedYearId != null) {
        final semSnapshot = await FirebaseFirestore.instance
            .collection('semesters')
            .where('academicYear', isEqualTo: matchedYearId)
            .where('isActive', isEqualTo: true)
            .get();

        if (semSnapshot.docs.isNotEmpty) {
          if (mounted) {
            setState(() {
              final semList = semSnapshot.docs
                  .map((d) => d['semesterNumber'].toString())
                  .toList();
              semList.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
              _availableSemesters = semList;
              if (!_availableSemesters.contains(_selectedSemester)) {
                _selectedSemester = _availableSemesters.last;
              }
              _isLoadingSemesters = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("Error loading student semesters: $e");
    }

    if (mounted) setState(() => _isLoadingSemesters = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Student Details", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: customRed,
        elevation: 0.5,
        centerTitle: true,
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: customRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: customRed.withOpacity(0.3)),
            ),
            child: _isLoadingSemesters
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : _availableSemesters.isEmpty
                    ? const Padding(padding: EdgeInsets.all(8.0), child: Text("No Active Semesters", style: TextStyle(fontSize: 12)))
                    : DropdownButton<String>(
                        value: _selectedSemester.isNotEmpty && _availableSemesters.contains(_selectedSemester) ? _selectedSemester : null,
                        dropdownColor: Colors.white,
                        icon: Icon(Icons.arrow_drop_down, color: customRed),
                        underline: const SizedBox(),
                        style: TextStyle(color: customRed, fontWeight: FontWeight.bold),
                        items: _availableSemesters.map((s) => DropdownMenuItem(
                          value: s,
                          child: Text("Sem $s", style: const TextStyle(color: Colors.black87)),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedSemester = val);
                        },
                      ),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            FutureBuilder<Map<String, dynamic>?>(
              future: FirebaseFirestore.instance
                  .collection('fee_structures')
                  .where('semester', isEqualTo: _selectedSemester)
                  .where('isActive', isEqualTo: true)
                  .get()
                  .then((snapshot) {
                    final sBatch = (widget.studentData['batch'] ?? '').toString().toLowerCase();
                    final sDept = (widget.studentData['dept'] ?? '').toString().toLowerCase();
                    final sQuota = (widget.studentData['quotaCategory'] ?? '').toString().toLowerCase();

                    try {
                      final matches = snapshot.docs.where((d) {
                        final data = d.data();
                        final fBatch = (data['academicYear'] ?? '').toString().toLowerCase();
                        final fDept = (data['dept'] ?? '').toString().toLowerCase();
                        final fQuota = (data['quotaCategory'] ?? '').toString().toLowerCase();

                        bool batchMatch = fBatch == sBatch || fBatch.contains(sBatch) || sBatch.contains(fBatch);
                        bool deptMatch = fDept == sDept || fDept == 'all';
                        bool quotaMatch = fQuota == sQuota || fQuota == 'all';

                        return batchMatch && deptMatch && quotaMatch;
                      }).toList();

                      if (matches.isEmpty) return null;
                      return matches.first.data();
                    } catch (e) {
                      debugPrint("Fee Structure Match Error: $e");
                      return null;
                    }
                  }),
              builder: (context, feeSnapshot) {
                final feeStructure = feeSnapshot.data;

                double totalFeeAmt = 0.0;
                if (feeStructure != null) {
                  totalFeeAmt = FeeService().calculateStudentFee(
                    feeStructure: feeStructure,
                    studentType: widget.studentData['studentType'] ?? 'day_scholar',
                    busPlace: widget.studentData['busPlace'],
                  );
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('payments')
                      .where('studentId', isEqualTo: widget.studentId)
                      .where('semester', isEqualTo: _selectedSemester)
                      .snapshots(),
                  builder: (context, paymentSnapshot) {
                    final payments = paymentSnapshot.data?.docs ?? [];

                    double totalPaidVerified = 0;
                    double totalPendingReview = 0;

                    for (var p in payments) {
                      final pData = p.data() as Map<String, dynamic>;
                      final amt = (pData['amount'] as num?)?.toDouble() ?? 0.0;

                      if (pData['status'] == 'verified') {
                        totalPaidVerified += amt;
                      } else if (pData['status'] == 'under_review') {
                        totalPendingReview += amt;
                      }
                    }

                    final double due = totalFeeAmt - totalPaidVerified;

                    if (feeStructure == null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text("No Fee Structure found for $_selectedSemester"),
                        ),
                      );
                    }

                    DateTime? mainDeadline = (feeStructure['deadline'] as Timestamp?)?.toDate();
                    DateTime? examDeadline = (feeStructure['examDeadline'] as Timestamp?)?.toDate();

                    Map<String, double> applicableFees = {};
                    Map<String, dynamic> components = feeStructure['components'] as Map<String, dynamic>? ?? {};
                    String sType = widget.studentData['studentType'] ?? 'day_scholar';
                    String? sBusPlace = widget.studentData['busPlace'];

                    components.forEach((key, value) {
                      if (key.toLowerCase().contains('hostel') && sType != 'hosteller') return;
                      if (key.toLowerCase().contains('bus')) {
                        if (sType == 'bus_user' && value is Map && sBusPlace != null && value.containsKey(sBusPlace)) {
                          applicableFees[key] = (value[sBusPlace] as num).toDouble();
                        }
                        return;
                      }
                      if (value is num) applicableFees[key] = value.toDouble();
                    });

                    if (feeStructure['examFee'] != null) {
                      applicableFees['Exam Fee'] = (feeStructure['examFee'] as num).toDouble();
                    }

                    bool mainOverdue = false;
                    bool examOverdue = false;

                    if (mainDeadline != null && DateTime.now().isAfter(mainDeadline)) {
                      double regularPaid = 0;
                      double regularTotal = 0;
                      applicableFees.forEach((k, v) {
                        if (k != 'Exam Fee') regularTotal += v;
                      });
                      payments.forEach((p) {
                        var pd = p.data() as Map<String, dynamic>;
                        if (pd['status'] == 'verified' && pd['feeType'] != 'Exam Fee') {
                          regularPaid += (pd['amount'] as num).toDouble();
                        }
                      });
                      if (regularPaid < regularTotal) mainOverdue = true;
                    }

                    if (examDeadline != null && DateTime.now().isAfter(examDeadline) && applicableFees.containsKey('Exam Fee')) {
                      double examPaid = 0;
                      payments.forEach((p) {
                        var pd = p.data() as Map<String, dynamic>;
                        if (pd['status'] == 'verified' && pd['feeType'] == 'Exam Fee') {
                          examPaid += (pd['amount'] as num).toDouble();
                        }
                      });
                      if (examPaid < applicableFees['Exam Fee']!) examOverdue = true;
                    }

                    String statusText = "PENDING";
                    Color statusColor = customRed.withOpacity(0.5);

                    if (feeSnapshot.connectionState == ConnectionState.waiting) {
                      statusText = "COMPUTING...";
                      statusColor = Colors.grey;
                    } else if (totalFeeAmt == 0) {
                      statusText = "NO FEE SET";
                      statusColor = Colors.grey;
                    } else if (due <= 0) {
                      statusText = "CLEARED";
                      statusColor = Colors.green;
                    } else if (mainOverdue || examOverdue) {
                      statusText = "OVERDUE";
                      statusColor = customRed;
                    } else if (totalPendingReview > 0) {
                      statusText = "VERIFICATION PENDING";
                      statusColor = Colors.orange;
                    }

                    // Determine header gradient based on clearance
                    bool isCleared = due <= 0;
                    final Gradient headerGradient = LinearGradient(
                      colors: isCleared
                          ? [customGreen, customGreen.withOpacity(0.8)]
                          : [customRed, customRed.withOpacity(0.85)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    );

                    return Column(
                      children: [
                        // Student Info Card with dynamic gradient
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: headerGradient,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: isCleared ? customGreen.withOpacity(0.3) : customRed.withOpacity(0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.studentData['name'] ?? "Unknown",
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                "Reg No: ${widget.studentData['regNo']}  |  Quota: ${widget.studentData['quotaCategory']}",
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 20),

                              // Stats Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _headerStatWhite("Paid (Verified)", "₹${totalPaidVerified.toStringAsFixed(0)}"),
                                  _headerStatWhite("Due", "₹${due.toStringAsFixed(0)}"),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: isCleared ? customGreen : customRed),
                                    ),
                                    child: Text(
                                      statusText,
                                      style: TextStyle(color: isCleared ? customGreen : customRed, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              if (totalPendingReview > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    "Pending Verify: ₹${totalPendingReview.toStringAsFixed(0)}",
                                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                                  ),
                                ),

                              // Overdue Alerts
                              if (mainOverdue)
                                Container(
                                  margin: const EdgeInsets.only(top: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.error, color: Colors.orangeAccent, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "Fees Overdue! Deadline: ${DateFormat('dd MMM yyyy').format(mainDeadline!)}",
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (examOverdue)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.assignment_late, color: Colors.orangeAccent, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "Exam Fee Overdue! Deadline: ${DateFormat('dd MMM yyyy').format(examDeadline!)}",
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              // No-Due Certificate Status
                              FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('no_due_certificates')
                                    .doc('${widget.studentId}_$_selectedSemester')
                                    .get(),
                                builder: (ctx, certSnap) {
                                  if (!certSnap.hasData || !certSnap.data!.exists) return const SizedBox.shrink();
                                  final certStatus = (certSnap.data!.data() as Map<String, dynamic>)['status'];
                                  Color chipColor = Colors.greenAccent;
                                  String chipLabel = "✅ No-Due Issued";
                                  if (certStatus == 'reissue_requested') {
                                    chipColor = Colors.orangeAccent;
                                    chipLabel = "⏳ Reissue Requested";
                                  } else if (certStatus == 'reissue_approved') {
                                    chipColor = Colors.lightBlueAccent;
                                    chipLabel = "🔓 Reissue Approved";
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        border: Border.all(color: chipColor),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        chipLabel,
                                        style: TextStyle(color: chipColor, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // Fee Breakdown Card
                        Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: isCleared ? customGreen.withOpacity(0.3) : customRed.withOpacity(0.3)),
                          ),
                          child: ExpansionTile(
                            title: const Text("Expected Fee Breakdown", style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              "Total: ₹${totalFeeAmt.toStringAsFixed(0)}",
                              style: TextStyle(color: isCleared ? customGreen : customRed),
                            ),
                            children: [
                              ...applicableFees.entries.map((e) => ListTile(
                                dense: true,
                                title: Text(e.key),
                                trailing: Text("₹${e.value.toStringAsFixed(0)}"),
                                leading: Icon(Icons.circle, size: 8, color: e.key == 'Exam Fee' ? Colors.purple : (isCleared ? customGreen : customRed)),
                              )),
                            ],
                          ),
                        ),

                        // Payment History Header with Statement Button
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Payment History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  List<Map<String, dynamic>> paymentList = payments.map((p) {
                                    final data = p.data() as Map<String, dynamic>;
                                    return {
                                      'date': data['submittedAt'],
                                      'transactionId': data['transactionId'],
                                      'amount': data['amount'],
                                      'status': data['status'],
                                    };
                                  }).toList();

                                  await PdfService().generateStudentStatement(
                                    widget.studentData,
                                    _selectedSemester,
                                    totalFeeAmt,
                                    totalPaidVerified,
                                    due > 0 ? due : 0,
                                    paymentList,
                                  );
                                },
                                icon: const Icon(Icons.picture_as_pdf, size: 16),
                                label: const Text("Statement"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isCleared ? customGreen : customRed,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              )
                            ],
                          ),
                        ),

                        // Payment List
                        if (payments.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text("No payments found for this semester."),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: payments.length,
                            itemBuilder: (context, index) {
                              var payData = payments[index].data() as Map<String, dynamic>;
                              String pStatus = payData['status'];
                              Color pColor = pStatus == 'verified'
                                  ? Colors.green
                                  : (pStatus == 'rejected' ? Colors.red : Colors.orange);

                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: pColor.withOpacity(0.1),
                                    child: Icon(
                                      pStatus == 'verified'
                                          ? Icons.check
                                          : (pStatus == 'rejected' ? Icons.close : Icons.hourglass_empty),
                                      color: pColor,
                                    ),
                                  ),
                                  title: Text("₹${payData['amount']}"),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("Txn: ${payData['transaction_id'] ?? payData['transactionId'] ?? 'N/A'}"),
                                      Text("Date: ${payData['submittedAt'] != null ? (payData['submittedAt'] as Timestamp).toDate().toString().split(' ')[0] : 'N/A'}"),
                                      if (payData['isInstallment'] == true)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: (isCleared ? customGreen : customRed).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: (isCleared ? customGreen : customRed).withOpacity(0.3)),
                                            ),
                                            child: Text(
                                              "Installment ${payData['installmentNumber'] ?? '?'} of ${payData['totalInstallments'] ?? 2}",
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isCleared ? customGreen : customRed,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Chip(
                                    label: Text(pStatus.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10)),
                                    backgroundColor: pColor,
                                  ),
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 30),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerStatWhite(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color.fromARGB(255, 255, 255, 255), fontSize: 12)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}