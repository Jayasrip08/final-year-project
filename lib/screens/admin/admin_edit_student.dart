import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminEditStudent extends StatefulWidget {
  final Map<String, dynamic> studentData;
  final String studentId;

  const AdminEditStudent({super.key, required this.studentData, required this.studentId});

  @override
  State<AdminEditStudent> createState() => _AdminEditStudentState();
}

class _AdminEditStudentState extends State<AdminEditStudent> {
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _regNoCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _parentPhoneCtrl;
  
  String? _selectedDept;
  String? _selectedBatch;
  String? _selectedQuota;
  String? _selectedType;
  String? _busPlace;

  bool _isLoading = false;

  final List<String> _types = ['day_scholar', 'hosteller', 'bus_user'];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.studentData['name']);
    _regNoCtrl = TextEditingController(text: widget.studentData['regNo']);
    _emailCtrl = TextEditingController(text: widget.studentData['email'] ?? 'No email');
    _selectedDept = widget.studentData['dept'];
    _selectedBatch = widget.studentData['batch'];
    _selectedQuota = widget.studentData['quotaCategory'];
    _selectedType = widget.studentData['studentType'] ?? 'day_scholar';
    _busPlace = widget.studentData['busPlace'];
    _parentPhoneCtrl = TextEditingController(text: widget.studentData['parentPhoneNumber'] ?? '');
  }

  Future<void> _updateStudent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.studentId).update({
        'name': _nameCtrl.text.trim(),
        'regNo': _regNoCtrl.text.trim(),
        'dept': _selectedDept,
        'batch': _selectedBatch,
        'quotaCategory': _selectedQuota,
        'studentType': _selectedType,
        'busPlace': _selectedType == 'bus_user' ? _busPlace : null,
        'parentPhoneNumber': _parentPhoneCtrl.text.trim().startsWith('+') 
            ? _parentPhoneCtrl.text.trim() 
            : '+91${_parentPhoneCtrl.text.trim()}',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Student Profile Updated")));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Student Profile"),
        backgroundColor: customRed,
        foregroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: customRed.withOpacity(0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Name
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: "Full Name",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: customRed, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.person_outline, color: customRed),
                    ),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                  ),
                  const SizedBox(height: 16),
                  // Register Number
                  TextFormField(
                    controller: _regNoCtrl,
                    decoration: InputDecoration(
                      labelText: "Register Number",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: customRed, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.badge_outlined, color: customRed),
                    ),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                  ),
                  const SizedBox(height: 16),
                  // Email
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: InputDecoration(
                      labelText: "Email ID",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: customRed, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.email_outlined, color: customRed),
                    ),
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  // Parent Phone
                  TextFormField(
                    controller: _parentPhoneCtrl,
                    decoration: InputDecoration(
                      labelText: "Parent's Phone Number",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: customRed, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.family_restroom_outlined, color: customRed),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.isEmpty || v.length < 10) ? "Enter valid phone number" : null,
                  ),
                  const SizedBox(height: 16),
                  
                  // Department
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('departments').orderBy('name').snapshots(),
                    builder: (context, snapshot) {
                      List<String> depts = [];
                      if (snapshot.hasData) {
                        depts = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                      }
                      
                      return DropdownButtonFormField<String>(
                        value: depts.contains(_selectedDept) ? _selectedDept : null,
                        decoration: InputDecoration(
                          labelText: "Department",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: customRed, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: Icon(Icons.school_outlined, color: customRed),
                        ),
                        icon: Icon(Icons.arrow_drop_down, color: customRed),
                        items: depts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                        onChanged: (val) => setState(() => _selectedDept = val),
                      );
                    }
                  ),
                  const SizedBox(height: 16),

                  // Batch
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('academic_years').snapshots(),
                    builder: (context, snapshot) {
                      List<String> batches = [];
                      if (snapshot.hasData) {
                        batches = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                        batches.sort((a, b) => b.compareTo(a));
                      }
                      if (_selectedBatch != null && !batches.contains(_selectedBatch)) {
                        batches.add(_selectedBatch!);
                      }
                      
                      return DropdownButtonFormField<String>(
                        value: batches.contains(_selectedBatch) ? _selectedBatch : null,
                        decoration: InputDecoration(
                          labelText: "Batch",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: customRed, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: Icon(Icons.calendar_today_outlined, color: customRed),
                        ),
                        icon: Icon(Icons.arrow_drop_down, color: customRed),
                        items: batches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                        onChanged: (val) => setState(() => _selectedBatch = val),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Quota
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('quotas').orderBy('name').snapshots(),
                    builder: (context, snapshot) {
                      List<String> quotas = [];
                      if (snapshot.hasData) {
                        quotas = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                      }

                      return DropdownButtonFormField<String>(
                        value: quotas.contains(_selectedQuota) ? _selectedQuota : null,
                        decoration: InputDecoration(
                          labelText: "Quota",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: customRed, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: Icon(Icons.assignment_outlined, color: customRed),
                        ),
                        icon: Icon(Icons.arrow_drop_down, color: customRed),
                        items: quotas.map((q) => DropdownMenuItem(value: q, child: Text(q))).toList(),
                        onChanged: (val) => setState(() => _selectedQuota = val),
                      );
                    }
                  ),
                  const SizedBox(height: 16),

                  // Student Type
                  DropdownButtonFormField<String>(
                    value: _selectedType,
                    decoration: InputDecoration(
                      labelText: "Student Type",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: customRed, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.person_outline, color: customRed),
                    ),
                    icon: Icon(Icons.arrow_drop_down, color: customRed),
                    items: _types.map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.toUpperCase().replaceAll("_", " ")),
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedType = val),
                  ),
                  const SizedBox(height: 16),

                  // Bus Place (Conditional)
                  if (_selectedType == 'bus_user')
                    TextFormField(
                      initialValue: _busPlace,
                      decoration: InputDecoration(
                        labelText: "Bus Place (Route)",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: customRed, width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: Icon(Icons.directions_bus_outlined, color: customRed),
                      ),
                      onChanged: (val) => _busPlace = val,
                    ),
                  
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _updateStudent,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: customRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                      child: _isLoading 
                        ? const CircularProgressIndicator(color: Colors.white) 
                        : const Text("Update Profile", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}