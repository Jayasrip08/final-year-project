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
  String _selectedBatch = "ALL"; 
  String _selectedSemester = "ALL";
  List<String> _availableSemesters = ["ALL"]; 
  bool _isLoading = false;

  Map<String, double> _metrics = {
    'expected': 0.0,
    'received': 0.0,
    'pending': 0.0,
    'outstanding': 0.0,
    'studentCount': 0.0,
  };

  @override
  void initState() {
    super.initState();
    _calculateAnalytics();
  }

  Future<void> _calculateAnalytics() async {
    if (!mounted) return;
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
      final paymentSnapshot = await paymentQuery.get();
      final payments = paymentSnapshot.docs;

      double totalExpected = 0.0;
      double totalReceived = 0.0;
      double totalPending = 0.0;

      final FeeService feeService = FeeService();
      final studentIdsInBatch = students.map((s) => s.id).toSet();

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

        List<String> semestersToCalc = (_selectedSemester != "ALL") 
            ? [_selectedSemester] 
            : ['1', '2', '3', '4', '5', '6', '7', '8'];

        for (var sem in semestersToCalc) {
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

      for (var p in payments) {
        final pData = p.data() as Map<String, dynamic>;
        final uid = pData['uid'];
        if (_selectedBatch != "ALL" && !studentIdsInBatch.contains(uid)) continue;
        
        double amount = (pData['amountPaid'] ?? pData['amount'] ?? 0).toDouble();
        String status = pData['status'] ?? 'under_review';
        if (status == 'verified') {
          totalReceived += amount;
        } else if (status == 'under_review') {
          totalPending += amount;
        }
      }

      // Update Semesters list logic
      Set<String> sems = {"ALL"};
      for (var f in feeStructures) {
        final sem = (f.data() as Map<String, dynamic>)['semester'];
        if (sem != null) sems.add(sem.toString());
      }
      List<String> sortedSems = sems.toList()..sort((a, b) => a == "ALL" ? -1 : b == "ALL" ? 1 : a.compareTo(b));

      if (mounted) {
        setState(() {
          _availableSemesters = sortedSems;
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
      debugPrint("Analytics Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryRed = Color(0xFFD32F2F); // Professional Deep Red

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Income Analytics", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      drawer: widget.drawer,
      body: RefreshIndicator(
        color: primaryRed,
        onRefresh: _calculateAnalytics,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // Header Section
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: primaryRed,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                child: _buildFilters(primaryRed),
              ),
              
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    if (_isLoading)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(100),
                        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(primaryRed)),
                      ))
                    else ...[
                      _buildSummaryCards(primaryRed),
                      const SizedBox(height: 25),
                      _buildVisualProgress(primaryRed),
                      const SizedBox(height: 30),
                      _buildInsightSection(primaryRed),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(Color accent) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('academic_years').snapshots(),
                builder: (context, snapshot) {
                  List<String> batches = ["ALL"];
                  if (snapshot.hasData) {
                    batches.addAll(snapshot.data!.docs.map((d) => d['name'] as String).toList());
                  }
                  return _filterDropdown(
                    label: "Batch",
                    value: _selectedBatch,
                    items: batches,
                    onChanged: (val) {
                      setState(() => _selectedBatch = val!);
                      _calculateAnalytics();
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _filterDropdown(
                label: "Semester",
                value: _selectedSemester,
                items: _availableSemesters,
                onChanged: (val) {
                  setState(() => _selectedSemester = val!);
                  _calculateAnalytics();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _filterDropdown({required String label, required String value, required List<String> items, required void Function(String?) onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFD32F2F)),
              items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontSize: 14)))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(Color primary) {
    return Column(
      children: [
        Row(
          children: [
            _metricCard("Expected", _metrics['expected']!, Colors.black87, Icons.account_balance),
            const SizedBox(width: 15),
            _metricCard("Received", _metrics['received']!, Colors.green, Icons.check_circle),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            _metricCard("Pending", _metrics['pending']!, Colors.orange[800]!, Icons.pending_actions),
            const SizedBox(width: 15),
            _metricCard("Outstanding", _metrics['outstanding']!, Colors.redAccent, Icons.warning),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                "₹${amount.toStringAsFixed(0)}",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualProgress(Color primary) {
    double percent = _metrics['expected'] == 0 ? 0 : (_metrics['received']! / _metrics['expected']!);
    if (percent > 1.0) percent = 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Collection Target", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("${(percent * 100).toStringAsFixed(1)}%", style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 8,
              backgroundColor: Colors.grey[100],
              valueColor: AlwaysStoppedAnimation<Color>(primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightSection(Color primary) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: primary.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, color: primary, size: 20),
              const SizedBox(width: 10),
              const Text("Business Insights", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const Divider(height: 25),
          _insightRow("Active Student Records", "${_metrics['studentCount']?.toInt() ?? 0}"),
          _insightRow("Avg. Recovery / Student", "₹${_calculateAvgRecovery()}"),
          _insightRow("Verification Success", "${_calculateVerificationRate()}%"),
        ],
      ),
    );
  }

  String _calculateAvgRecovery() {
    if (_metrics['studentCount'] == 0) return "0";
    return (_metrics['received']! / _metrics['studentCount']!).toStringAsFixed(0);
  }

  String _calculateVerificationRate() {
    double totalTransacted = _metrics['received']! + _metrics['pending']!;
    if (totalTransacted == 0) return "0";
    return ((_metrics['received']! / totalTransacted) * 100).toStringAsFixed(1);
  }

  Widget _insightRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}