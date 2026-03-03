import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/fee_service.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  final Widget? drawer;
  const AdminAnalyticsScreen({super.key, this.drawer});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  String? _selectedBatch = "ALL"; // Default to institutional view
  String? _selectedSemester = "ALL";
  List<String> _availableSemesters = ["ALL"]; // Track semesters with data
  bool _isLoading = false;

  Map<String, double> _metrics = {
    'expected': 0.0,
    'received': 0.0,
    'pending': 0.0,
    'outstanding': 0.0,
    'studentCount': 0.0, // Added to track student count
  };

  @override
  void initState() {
    super.initState();
    _calculateAnalytics();
  }

  Future<void> _calculateAnalytics() async {
    setState(() => _isLoading = true);

    try {
      // 1. Fetch Students
      Query studentQuery = FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'student');
      if (_selectedBatch != "ALL") {
        studentQuery = studentQuery.where('batch', isEqualTo: _selectedBatch);
      }
      final studentsSnapshot = await studentQuery.get();
      final students = studentsSnapshot.docs;

      // 2. Fetch Fee Structures
      Query feeQuery = FirebaseFirestore.instance.collection('fee_structures').where('isActive', isEqualTo: true);
      if (_selectedBatch != "ALL") {
        feeQuery = feeQuery.where('academicYear', isEqualTo: _selectedBatch);
      }
      if (_selectedSemester != "ALL") {
        feeQuery = feeQuery.where('semester', isEqualTo: _selectedSemester);
      }
      final feeSnapshot = await feeQuery.get();
      final feeStructures = feeSnapshot.docs;

      // 3. Fetch Payments
      Query paymentQuery = FirebaseFirestore.instance.collection('payments');
      if (_selectedSemester != "ALL") {
        paymentQuery = paymentQuery.where('semester', isEqualTo: _selectedSemester);
      }
      // Note: We'll filter payments by student UID client-side if Batch is selected
      final paymentSnapshot = await paymentQuery.get();
      final payments = paymentSnapshot.docs;

      // --- AGGREGATION LOGIC ---
      double totalExpected = 0.0;
      double totalReceived = 0.0;
      double totalPending = 0.0;

      final FeeService feeService = FeeService();
      final studentIdsInBatch = students.map((s) => s.id).toSet();

      // Calculation of Expected
      // We need to match each student with their relevant fee structures
      // For performance, we'll group structures by Batch/Semester/Dept/Quota
      Map<String, dynamic> structuresMap = {};
      for (var f in feeStructures) {
        final data = f.data() as Map<String, dynamic>;
        String key = "${data['academicYear']}_${data['semester']}_${data['dept']}_${data['quotaCategory']}";
        structuresMap[key] = data;
      }

      for (var studentDoc in students) {
        final sData = studentDoc.data() as Map<String, dynamic>;
        String batch = sData['batch'] ?? '';
        String dept = sData['dept'] ?? '';
        String quota = sData['quotaCategory'] ?? '';
        String studentType = sData['studentType'] ?? 'day_scholar';

        List<String> semestersToCalc = [];
        if (_selectedSemester != "ALL") {
           semestersToCalc.add(_selectedSemester!);
        } else {
           // If ALL semesters, we sum up for all semesters that have structures defined
           // A better way might be to only sum up to the student's current semester, 
           // but for simple institutional analytics, we'll sum all defined for now.
           semestersToCalc = [ '1', '2', '3', '4', '5', '6', '7', '8' ];
        }

        for (var sem in semestersToCalc) {
          // Find matching structure (General to Specific)
          Map<String, dynamic>? bestMatch;
          
          List<String> keysToTry = [
            "${batch}_${sem}_${dept}_$quota",
            "${batch}_${sem}_All_$quota",
            "${batch}_${sem}_${dept}_All",
            "${batch}_${sem}_All_All",
          ];

          for (var k in keysToTry) {
            if (structuresMap.containsKey(k)) {
              bestMatch = structuresMap[k];
              break;
            }
          }

          if (bestMatch != null) {
            totalExpected += feeService.calculateStudentFee(
              feeStructure: bestMatch,
              studentType: studentType,
              busPlace: sData['busPlace'],
            );
          }
        }
      }

      // Calculation of Received / Pending
      for (var p in payments) {
        final pData = p.data() as Map<String, dynamic>;
        final uid = pData['uid'];
        
        // Filter by batch if needed
        if (_selectedBatch != "ALL" && !studentIdsInBatch.contains(uid)) continue;

        double amount = (pData['amountPaid'] ?? pData['amount'] ?? 0).toDouble();
        String status = pData['status'] ?? 'under_review';

        if (status == 'verified') {
          totalReceived += amount;
        } else if (status == 'under_review') {
          totalPending += amount;
        }
      }

      // 4. Update Available Semesters list based on fetched fee structures
      // Note: Only do this when Batch changes or on initial load
      Set<String> sems = {"ALL"};
      for (var f in feeStructures) {
        final sem = (f.data() as Map<String, dynamic>)['semester'];
        if (sem != null) sems.add(sem.toString());
      }
      List<String> sortedSems = sems.toList()..sort((a, b) => a == "ALL" ? -1 : b == "ALL" ? 1 : a.compareTo(b));

      if (mounted) {
        setState(() {
          _availableSemesters = sortedSems;
          // Reset selected semester if it's no longer available
          if (!_availableSemesters.contains(_selectedSemester)) {
            _selectedSemester = "ALL";
          }
          
          _metrics = {
            'expected': totalExpected,
            'received': totalReceived,
            'pending': totalPending,
            'outstanding': totalExpected - totalReceived,
            'studentCount': students.length.toDouble(),
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Analytics Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error calculating analytics: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Income Analytics"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      drawer: widget.drawer,
      body: RefreshIndicator(
        onRefresh: _calculateAnalytics,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFilters(),
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ))
              else ...[
                _buildSummaryCards(),
                const SizedBox(height: 24),
                _buildVisualProgress(),
                const SizedBox(height: 32),
                _buildDetailedBreakdownHeader(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Institutional Filter", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('academic_years').snapshots(),
                    builder: (context, snapshot) {
                      List<String> batches = ["ALL"];
                      if (snapshot.hasData) {
                        batches.addAll(snapshot.data!.docs.map((d) => d['name'] as String).toList());
                        // Sort so newest is first after ALL
                        if (batches.length > 1) {
                          var actualBatches = batches.sublist(1);
                          actualBatches.sort((a,b) => b.compareTo(a));
                          batches = ["ALL", ...actualBatches];
                        }
                      }
                      return DropdownButtonFormField<String>(
                        value: _selectedBatch,
                        decoration: InputDecoration(
                          labelText: "Batch",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: batches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                        onChanged: (val) {
                          setState(() => _selectedBatch = val);
                          _calculateAnalytics();
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedSemester,
                    decoration: InputDecoration(
                      labelText: "Semester",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _availableSemesters.map((s) => DropdownMenuItem(
                      value: s, 
                      child: Text(s == "ALL" ? "All Semesters" : "Semester $s")
                    )).toList(),
                    onChanged: (val) {
                      setState(() => _selectedSemester = val);
                      _calculateAnalytics();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      children: [
        Row(
          children: [
            _metricCard("Total Expected", _metrics['expected']!, Colors.blue, Icons.payments),
            const SizedBox(width: 12),
            _metricCard("Total Received", _metrics['received']!, Colors.green, Icons.check_circle),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _metricCard("Pending Review", _metrics['pending']!, Colors.orange, Icons.history),
            const SizedBox(width: 12),
            _metricCard("Outstanding", _metrics['outstanding']!, Colors.red, Icons.warning_amber),
          ],
        ),
      ],
    );
  }

  Widget _metricCard(String title, double amount, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: color.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                "₹${amount.toStringAsFixed(0)}",
                style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualProgress() {
    double percent = _metrics['expected'] == 0 ? 0 : (_metrics['received']! / _metrics['expected']!);
    if (percent > 1.0) percent = 1.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Collection Progress", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text("${(percent * 100).toStringAsFixed(1)}%", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 12,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(percent > 0.8 ? Colors.green : Colors.indigo),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedBreakdownHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Quick Insights", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        _insightRow("Active Students in Search", "${_calculateActiveStudentsInSearch()}"),
        _insightRow("Avg. Recovery per Student", "₹${_calculateAvgRecovery()}"),
        _insightRow("Verification Rate", "${_calculateVerificationRate()}%"),
      ],
    );
  }

  int _calculateActiveStudentsInSearch() {
    return _metrics['studentCount']?.toInt() ?? 0;
  }

  String _calculateAvgRecovery() {
    if (_metrics['studentCount'] == 0) return "₹0";
    double avg = _metrics['received']! / _metrics['studentCount']!;
    return "₹${avg.toStringAsFixed(0)}";
  }

  String _calculateVerificationRate() {
    if (_metrics['received']! + _metrics['pending']! == 0) return "0";
    return ((_metrics['received']! / (_metrics['received']! + _metrics['pending']!)) * 100).toStringAsFixed(1);
  }

  Widget _insightRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
