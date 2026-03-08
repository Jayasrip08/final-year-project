import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'staff_student_detail.dart';
import '../profile_screen.dart';
import '../../services/pdf_service.dart';

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  String? _staffDept;
  bool _isLoading = true;
  String _loadingMessage = "Loading department data...";

  // PROFESSIONAL RED & WHITE THEME
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);
  final Color backgroundWhite = const Color(0xFFF8F9FA);

  // Data Store
  List<Map<String, dynamic>> _allStudents = []; 
  List<String> _batches = [];
  
  // Filters
  String _searchQuery = "";
  String? _selectedBatch;
  String _selectedStatus = 'All'; 

  // Navigation State
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // Logic: Load Data (Unchanged as requested)
  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = "Fetching department info...";
    });

    try {
      final staffDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUserId).get();
      if (!staffDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }
      _staffDept = staffDoc.data()?['dept'];

      if (_staffDept == null) {
        setState(() => _isLoading = false);
        return;
      }

      setState(() => _loadingMessage = "Loading fee structures...");

      final feeSnapshot = await FirebaseFirestore.instance
          .collection('fee_structures')
          .where('isActive', isEqualTo: true)
          .get();
      
      final feeStructures = feeSnapshot.docs.map((d) => d.data()).toList();

      setState(() => _loadingMessage = "Loading students & payments...");

      final activeBatchesSnapshot = await FirebaseFirestore.instance
          .collection('academic_years')
          .where('isActive', isEqualTo: true)
          .get();
      
      final activeBatchNames = activeBatchesSnapshot.docs
          .map((d) => d['name'].toString().toLowerCase().trim())
          .toSet();

      final studentSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'student')
          .where('dept', isEqualTo: _staffDept)
          .get();

      final paymentSnapshot = await FirebaseFirestore.instance
          .collection('payments')
          .where('dept', isEqualTo: _staffDept)
          .get();

      List<Map<String, dynamic>> processedList = [];
      Set<String> batchesFound = {};

      for (var doc in studentSnapshot.docs) {
        final data = doc.data();
        final String uid = doc.id;
        final String batch = (data['batch'] ?? '').toString();
        
        if (!activeBatchNames.contains(batch.toLowerCase().trim())) {
           continue; 
        }

        if (batch.isNotEmpty) batchesFound.add(batch);
        
        final String studentType = data['studentType'] ?? 'day_scholar';
        final String quota = data['quotaCategory'] ?? 'Management';
        final String busPlace = data['busPlace'] ?? '';

        final feeDetails = _calculateFeeDetails(feeStructures, batch, data['dept'] ?? '', studentType, quota, busPlace);
        double totalFee = (feeDetails['amount'] as num).toDouble();
        double mainFee = (feeDetails['mainFee'] as num).toDouble();
        double examFee = (feeDetails['examFee'] as num).toDouble();
        DateTime? mainDeadline = feeDetails['deadline'];
        DateTime? examDeadline = feeDetails['examDeadline'];
        
        double verifiedPaid = 0;
        double pendingPaid = 0;
        double verifiedMain = 0;
        double verifiedExam = 0;
        
        for (var p in paymentSnapshot.docs) {
          if (p['studentId'] == uid) {
             final amount = (p['amount'] as num).toDouble();
             final status = p['status'] ?? 'pending';
             final pType = p['feeType'];
             
             if (status == 'verified') {
               verifiedPaid += amount;
               if (pType == 'Exam Fee') {
                 verifiedExam += amount;
               } else {
                 verifiedMain += amount;
               }
             } else if (status == 'pending') {
               pendingPaid += amount;
             }
          }
        }

        double balance = totalFee - verifiedPaid;
        if (balance < 0) balance = 0;

        bool isOverdue = false;
        bool mainOverdue = false;
        if (mainDeadline != null && DateTime.now().isAfter(mainDeadline)) {
           if (verifiedMain < mainFee) mainOverdue = true;
        }
        bool examOverdue = false;
        if (examDeadline != null && DateTime.now().isAfter(examDeadline)) {
           if (verifiedExam < examFee) examOverdue = true;
        }
        if (mainOverdue || examOverdue) isOverdue = true;

        processedList.add({
          'uid': uid,
          'name': data['name'] ?? 'Unknown',
          'regNo': data['regNo'] ?? '',
          'batch': batch,
          'totalFee': totalFee,
          'verifiedPaid': verifiedPaid,
          'pendingPaid': pendingPaid,
          'balance': balance,
          'isOverdue': isOverdue,
          'rawData': data, 
        });
      }

      final Map<String, Map<String, dynamic>> uniqueStudents = {};
      for (var s in processedList) {
        final regNo = (s['regNo'] as String).trim();
        final uid = s['uid'];
        if (regNo.isEmpty) {
          uniqueStudents[uid] = s;
          continue;
        }
        if (uniqueStudents.containsKey(regNo)) {
          final existing = uniqueStudents[regNo]!;
          final double existingPaid = (existing['verifiedPaid'] as double) + (existing['pendingPaid'] as double);
          final double currentPaid = (s['verifiedPaid'] as double) + (s['pendingPaid'] as double);
          if (currentPaid > existingPaid) uniqueStudents[regNo] = s;
        } else {
          uniqueStudents[regNo] = s;
        }
      }

      if (mounted) {
        setState(() {
          _allStudents = uniqueStudents.values.toList();
          _batches = batchesFound.toList()..sort();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  // Logic: Calculate Fee (Unchanged)
  Map<String, dynamic> _calculateFeeDetails(List<Map<String, dynamic>> structures, String batch, String dept, String type, String quota, String busPlace) {
    double total = 0;
    double examFee = 0;
    DateTime? earliestDeadline;
    DateTime? examDeadline;

    for (var struct in structures) {
      final sDept = struct['dept'] ?? 'All';
      if (sDept != 'All' && sDept != dept) continue;
      final sBatch = struct['academicYear'] ?? 'All';
      if (sBatch != 'All' && !sBatch.contains(batch) && !batch.contains(sBatch)) continue;

      if (struct['deadline'] != null) {
        final DateTime? dt = (struct['deadline'] as Timestamp?)?.toDate();
        if (dt != null && (earliestDeadline == null || dt.isBefore(earliestDeadline))) {
          earliestDeadline = dt;
        }
      }
      if (struct['examDeadline'] != null) {
         examDeadline = (struct['examDeadline'] as Timestamp?)?.toDate();
      }
      if (struct['examFee'] != null) {
          double ef = (struct['examFee'] as num).toDouble();
          examFee += ef;
          total += ef;
      }
      final components = struct['components'] as Map<String, dynamic>? ?? {};
      for (var entry in components.entries) {
        String key = entry.key;
        dynamic value = entry.value;
        double amountToAdd = 0;

        if (key.contains('Bus')) {
          if (type != 'bus_user') continue;
          if (value is Map) amountToAdd = (value[busPlace] as num?)?.toDouble() ?? 0;
          else if (value is num) amountToAdd = value.toDouble();
        } 
        else if (key.contains('Hostel')) {
          if (type != 'hosteller') continue;
          if (value is Map) amountToAdd = (value['Standard'] as num?)?.toDouble() ?? 0;
          else if (value is num) amountToAdd = value.toDouble();
        }
        else {
          if (value is num) amountToAdd = value.toDouble();
          else if (value is Map) {
             var qKey = value.keys.firstWhere((k) => k.toString().toLowerCase() == quota.toLowerCase(), orElse: () => '');
             if (qKey.isNotEmpty) amountToAdd = (value[qKey] as num?)?.toDouble() ?? 0;
          }
        }
        total += amountToAdd;
      }
    }
    double mainFee = total - examFee;
    return { 'amount': total, 'mainFee': mainFee, 'examFee': examFee, 'deadline': earliestDeadline, 'examDeadline': examDeadline };
  }

  List<Map<String, dynamic>> _getFilteredList() {
    return _allStudents.where((s) {
      final searchLower = _searchQuery.toLowerCase();
      if (searchLower.isNotEmpty) {
        final name = s['name'].toString().toLowerCase();
        final reg = s['regNo'].toString().toLowerCase();
        if (!name.contains(searchLower) && !reg.contains(searchLower)) return false;
      }
      if (_selectedBatch != null && s['batch'] != _selectedBatch) return false;

      final balance = s['balance'] as double;
      final pendingAmount = s['pendingPaid'] as double;
      final totalFee = s['totalFee'] as double;

      if (_selectedStatus == 'Verified') {
        if (balance > 0 || totalFee == 0) return false;
      } else if (_selectedStatus == 'Pending') {
         if (pendingAmount <= 0) return false;
      } else if (_selectedStatus == 'Overdue') {
         if (s['isOverdue'] != true) return false;
      } else if (_selectedStatus == 'Not Paid') {
         if (balance <= 0 || pendingAmount > 0) return false;
      }
      return true;
    }).toList();
  }

  // Multi-Select State
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  void _toggleSelection(String uid) {
    setState(() {
      if (_selectedIds.contains(uid)) {
        _selectedIds.remove(uid);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(uid);
      }
    });
  }

  void _enterSelectionMode(String uid) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(uid);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _downloadReport() async {
    var targetList = <Map<String, dynamic>>[];
    if (_isSelectionMode && _selectedIds.isNotEmpty) {
      targetList = _allStudents.where((s) => _selectedIds.contains(s['uid'])).toList();
    } else {
      targetList = _getFilteredList();
    }
    if (targetList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data for report")));
      return;
    }
    await PdfService().generateDeptReport(_staffDept ?? "Dept", _selectedBatch, _selectedStatus, targetList);
    if (_isSelectionMode) _exitSelectionMode();
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _getFilteredList();

    return Scaffold(
      backgroundColor: backgroundWhite,
      appBar: AppBar(
        elevation: 0,
        leading: _isSelectionMode 
          ? IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectionMode) 
          : null,
        title: Text(
          _isSelectionMode ? "${_selectedIds.length} Selected" : (_staffDept != null ? "$_staffDept Staff" : "Staff Console"),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: _isSelectionMode ? Colors.black : customRed,
        foregroundColor: Colors.white,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Index 0: DASHBOARD
          Column(
            children: [
              _buildHeader(filteredList.length),
              _buildFilterSection(),
              Expanded(
                child: _isLoading 
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: customRed), const SizedBox(height: 10), Text(_loadingMessage)]))
                : filteredList.isEmpty
                    ? const Center(child: Text("No records found.", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        itemCount: filteredList.length,
                        itemBuilder: (ctx, i) => _buildStudentCard(filteredList[i]),
                      ),
              ),
            ],
          ),
          // Index 1 & 2: Placeholders (Actions handled by Navigation logic)
          const SizedBox.shrink(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          selectedItemColor: customRed,
          unselectedItemColor: Colors.grey[400],
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          onTap: (index) {
            if (index == 1) {
              _downloadReport(); // Instant Action
            } else {
              setState(() => _currentIndex = index);
            }
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.cloud_download_rounded), label: 'Download'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      decoration: BoxDecoration(
        color: customRed,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Text(
        "Overview: $count student(s) active",
        style: const TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildFilterSection() {
    if (_isSelectionMode) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search Name or Registration No...",
                prefixIcon: Icon(Icons.search, color: customRed),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildCustomDropdown(_selectedBatch, "Batch", _batches, (v) => setState(() => _selectedBatch = v))),
              const SizedBox(width: 12),
              Expanded(child: _buildCustomDropdown(_selectedStatus, "Status", ['All', 'Verified', 'Overdue', 'Not Paid'], (v) => setState(() => _selectedStatus = v!))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomDropdown(String? val, String hint, List<String> items, Function(String?) onChange) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: val == 'All' && hint == "Status" ? 'All' : val,
          hint: Text(hint, style: const TextStyle(fontSize: 13)),
          isExpanded: true,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: onChange,
        ),
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> item) {
    final uid = item['uid'];
    final balance = item['balance'] as double;
    final pendingAmount = item['pendingPaid'] as double;
    final totalFee = item['totalFee'] as double;
    final isSelected = _selectedIds.contains(uid);

    bool isPaid = balance <= 0;
    bool isPending = pendingAmount > 0;
    bool isNoFee = totalFee == 0;
    bool isOverdue = item['isOverdue'] == true;

    Color statusColor;
    String statusText;

    if (isNoFee) { statusColor = Colors.grey; statusText = "Pending Config"; }
    else if (isPaid) { statusColor = Colors.green[700]!; statusText = "Settled"; }
    else if (isPending) { statusColor = Colors.orange[800]!; statusText = "Verifying"; }
    else if (isOverdue) { statusColor = customRed; statusText = "Overdue"; }
    else { statusColor = Colors.blueGrey; statusText = "Dues"; }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isSelected ? Border.all(color: customRed, width: 2) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        onTap: () {
          if (_isSelectionMode) _toggleSelection(uid);
          else Navigator.push(context, MaterialPageRoute(builder: (_) => StaffStudentDetail(studentData: item['rawData'], studentId: uid)));
        },
        onLongPress: () => _enterSelectionMode(uid),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: isSelected ? customRed : statusColor.withOpacity(0.1),
          child: isSelected 
            ? const Icon(Icons.check, color: Colors.white) 
            : Text(item['name'][0].toUpperCase(), style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2D3436))),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text("${item['regNo']} | Batch ${item['batch']}", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(statusText.toUpperCase(), style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text("₹${balance.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}