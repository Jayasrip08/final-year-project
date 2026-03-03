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
  String _selectedSemester = ''; // Default empty
  List<String> _availableSemesters = []; // Default empty
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
      // 1. Find matching Academic Year
      final yearsSnapshot = await FirebaseFirestore.instance
          .collection('academic_years')
          .where('isActive', isEqualTo: true)
          .get();

      String? matchedYearId;
      // Prioritize exact match first
      for (var doc in yearsSnapshot.docs) {
        final yName = doc['name'].toString().toLowerCase();
        if (yName == sBatch) {
          matchedYearId = doc.id;
          break;
        }
      }
      // Fallback to contains
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
        // 2. Fetch Semesters for this Year
        final semSnapshot = await FirebaseFirestore.instance
            .collection('semesters')
            .where('academicYear', isEqualTo: matchedYearId)
            .where('isActive', isEqualTo: true) // Only active semesters for students
            //.orderBy('semesterNumber') // Removed to avoid index error
            .get();

        if (semSnapshot.docs.isNotEmpty) {
          if (mounted) {
            setState(() {
              final semList = semSnapshot.docs
                  .map((d) => d['semesterNumber'].toString())
                  .toList();
              
              // Sort numerically
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
      appBar: AppBar(
        title: const Text("Student Details"),
        actions: [
          // Semester Dropdown in AppBar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
              child: _isLoadingSemesters 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : _availableSemesters.isEmpty
                      ? const Padding(padding: EdgeInsets.all(8.0), child: Text("No Active Semesters", style: TextStyle(color: Colors.white, fontSize: 12)))
                      : DropdownButton<String>(
                          value: _selectedSemester.isNotEmpty && _availableSemesters.contains(_selectedSemester) ? _selectedSemester : null,
                          dropdownColor: Colors.indigo,
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                          underline: const SizedBox(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          items: _availableSemesters.map((s) => DropdownMenuItem(value: s, child: Text("Sem $s"))).toList(),
                          onChanged: (val) {
                            if(val != null) setState(() => _selectedSemester = val);
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
                        // Robust Dart Filtering
                        final matches = snapshot.docs.where((d) {
                          final data = d.data();
                          final fBatch = (data['academicYear'] ?? '').toString().toLowerCase();
                          final fDept = (data['dept'] ?? '').toString().toLowerCase();
                          final fQuota = (data['quotaCategory'] ?? '').toString().toLowerCase();
                          
                          // 1. Batch Match (Relaxed)
                          bool batchMatch = fBatch == sBatch || fBatch.contains(sBatch) || sBatch.contains(fBatch);
                          
                          // 2. Dept Match (Exact, Case-Insensitive)
                          bool deptMatch = fDept == sDept || fDept == 'all';
                          
                          // 3. Quota Match (Exact, Case-Insensitive)
                          bool quotaMatch = fQuota == sQuota || fQuota == 'all';
  
                          return batchMatch && deptMatch && quotaMatch;
                        }).toList();
                        
                        if (matches.isEmpty) return null;
                        return matches.first.data();
                      } catch (e) {
                        debugPrint("Fee Structure Match Error: $e");
                        return null; // No match found
                      }
                    }),
              builder: (context, feeSnapshot) {
                final feeStructure = feeSnapshot.data;
                
                // Calculate Total Fee Requirement
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
                      .where('semester', isEqualTo: _selectedSemester) // Filter by selected sem
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
                    
                    // --- DETAILED STATUS LOGIC ---
                    
                    if (feeStructure == null) {
                       // Return simplified view if no structure found
                       return Center(child: Text("No Fee Structure found for $_selectedSemester"));
                    }
                    
                    // 1. Get Deadlines
                    DateTime? mainDeadline = (feeStructure['deadline'] as Timestamp?)?.toDate();
                    DateTime? examDeadline = (feeStructure['examDeadline'] as Timestamp?)?.toDate();
                    
                    // 2. Identify Applicable Fees
                    Map<String, double> applicableFees = {};
                    Map<String, dynamic> components = feeStructure['components'] as Map<String, dynamic>? ?? {};
                    String sType = widget.studentData['studentType'] ?? 'day_scholar';
                    String? sBusPlace = widget.studentData['busPlace'];
                    
                    // Regular Components
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
                    
                    // Exam Fee
                    if (feeStructure['examFee'] != null) {
                      applicableFees['Exam Fee'] = (feeStructure['examFee'] as num).toDouble();
                    }
                    
                    // 3. Check Overdue Status
                    bool mainOverdue = false;
                    bool examOverdue = false;
                    
                    // Check Regular Fees
                    if (mainDeadline != null && DateTime.now().isAfter(mainDeadline)) {
                       double regularPaid = 0;
                       double regularTotal = 0;
                       
                       applicableFees.forEach((k, v) {
                         if (k != 'Exam Fee') regularTotal += v;
                       });
                       
                       // Calculate paid for regular fees
                       payments.forEach((p) {
                          var pd = p.data() as Map<String, dynamic>;
                          if (pd['status'] == 'verified' && pd['feeType'] != 'Exam Fee') {
                             regularPaid += (pd['amount'] as num).toDouble();
                          }
                       });
                       
                       if (regularPaid < regularTotal) mainOverdue = true;
                    }

                    // Check Exam Fee
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

                    // Status Logic
                    String statusText = "PENDING";
                    Color statusColor = Colors.orange;
                    
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
                      statusColor = Colors.red;
                    } else if (totalPendingReview > 0) {
                      statusText = "VERIFICATION PENDING";
                      statusColor = Colors.orange;
                    }

                    return Column(
                      children: [
                        // STUDENT INFO HEADER with Stats
                        Container(
                          padding: const EdgeInsets.all(20),
                          color: Colors.indigo,
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.studentData['name'] ?? "Unknown", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                              const SizedBox(height: 5),
                              Text("Reg No: ${widget.studentData['regNo']}  |  Quota: ${widget.studentData['quotaCategory']}", style: const TextStyle(color: Colors.white70)),
                              const SizedBox(height: 20),
                              
                              // STATS ROW simplified
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _headerStat("Paid (Verified)", "₹${totalPaidVerified.toStringAsFixed(0)}"),
                                  // Status Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                                    child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                  )
                                ],
                              ),
                              if (totalPendingReview > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text("Pending Verify: ₹${totalPendingReview.toStringAsFixed(0)}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                                ),
                              
                              // OVERDUE ALERTS
                              if (mainOverdue)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error, color: Colors.orangeAccent, size: 16),
                                      const SizedBox(width: 5),
                                      Text("Fees Overdue! Deadline: ${DateFormat('dd MMM').format(mainDeadline!)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              if (examOverdue)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.assignment_late, color: Colors.orangeAccent, size: 16),
                                      const SizedBox(width: 5),
                                      Text("Exam Fee Overdue! Deadline: ${DateFormat('dd MMM').format(examDeadline!)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ],
                                  ),
                                ),

                              // NO-DUE CERTIFICATE STATUS
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
                                  if (certStatus == 'reissue_requested') { chipColor = Colors.orangeAccent; chipLabel = "⏳ Reissue Requested"; }
                                  else if (certStatus == 'reissue_approved') { chipColor = Colors.lightBlueAccent; chipLabel = "🔓 Reissue Approved"; }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: chipColor.withOpacity(0.2), border: Border.all(color: chipColor), borderRadius: BorderRadius.circular(20)),
                                      child: Text(chipLabel, style: TextStyle(color: chipColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // FEE BREAKDOWN CARD (Read Only)
                        Card(
                          margin: const EdgeInsets.all(16),
                          elevation: 3,
                          child: ExpansionTile(
                            title: const Text("Expected Fee Breakdown", style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("Total: ₹${totalFeeAmt.toStringAsFixed(0)}"),
                            children: [
                               ...applicableFees.entries.map((e) => ListTile(
                                 dense: true,
                                 title: Text(e.key),
                                 trailing: Text("₹${e.value}"),
                                 leading: Icon(Icons.circle, size: 8, color: e.key == 'Exam Fee' ? Colors.purple : Colors.indigo),
                               )),
                            ],
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Payment History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  // Prepare data for PDF
                                  List<Map<String, dynamic>> paymentList = payments.map((p) {
                                    final data = p.data() as Map<String, dynamic>;
                                    return {
                                      'date': data['submittedAt'], // Timestamp
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
                                    paymentList
                                  );
                                },
                                icon: const Icon(Icons.picture_as_pdf, size: 16),
                                label: const Text("Statement"),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                              )
                            ],
                          ),
                        ),
                        // ... payments list ...

                        // PAYMENT LIST
                        if (payments.isEmpty)
                           const Padding(padding: EdgeInsets.all(20), child: Text("No payments found for this semester."))
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: payments.length,
                            itemBuilder: (context, index) {
                              var payData = payments[index].data() as Map<String, dynamic>;
                              String pStatus = payData['status'];
                              Color pColor = pStatus == 'verified' ? Colors.green : (pStatus == 'rejected' ? Colors.red : Colors.orange);

                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: pColor.withOpacity(0.1),
                                    child: Icon(pStatus == 'verified' ? Icons.check : (pStatus == 'rejected' ? Icons.close : Icons.hourglass_empty), color: pColor),
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
                                              color: Colors.blue.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                                            ),
                                            child: Text(
                                              "Installment ${payData['installmentNumber'] ?? '?'} of ${payData['totalInstallments'] ?? 2}",
                                              style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
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

  Widget _headerStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
