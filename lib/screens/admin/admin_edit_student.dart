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
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _regNoCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _parentPhoneCtrl; // NEW
  
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
    _selectedBatch = widget.studentData['batch']; // This might need to come from academic_years
    _selectedQuota = widget.studentData['quotaCategory'];
    _selectedType = widget.studentData['studentType'] ?? 'day_scholar';
    _busPlace = widget.studentData['busPlace'];
    _parentPhoneCtrl = TextEditingController(text: widget.studentData['parentPhoneNumber'] ?? ''); // NEW
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
        'busPlace': _selectedType == 'bus_user' ? _busPlace : null, // Clear bus place if not bus user
        'parentPhoneNumber': _parentPhoneCtrl.text.trim().startsWith('+') 
            ? _parentPhoneCtrl.text.trim() 
            : '+91${_parentPhoneCtrl.text.trim()}', // Enforce +91
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Student Profile Updated")));
        Navigator.pop(context, true); // Return true to trigger refresh
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
      appBar: AppBar(title: const Text("Edit Student Profile"), backgroundColor: Colors.indigo),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _regNoCtrl,
                decoration: const InputDecoration(labelText: "Register Number", border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: "Email ID", border: OutlineInputBorder()),
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _parentPhoneCtrl,
                decoration: const InputDecoration(
                  labelText: "Parent's Phone Number", 
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.family_restroom_outlined),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.isEmpty || v.length < 10) ? "Enter valid phone number" : null,
              ),
              const SizedBox(height: 15),
              
              // DEPT
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('departments').orderBy('name').snapshots(),
                builder: (context, snapshot) {
                  List<String> depts = [];
                  if (snapshot.hasData) {
                    depts = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                  }
                  // Fallback or current value if list is empty or loading
                  
                  return DropdownButtonFormField<String>(
                    value: depts.contains(_selectedDept) ? _selectedDept : null,
                    decoration: const InputDecoration(labelText: "Department", border: OutlineInputBorder()),
                    items: depts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (val) => setState(() => _selectedDept = val),
                  );
                }
              ),
              const SizedBox(height: 15),

              // BATCH (Fetch from academic_years or just Input)
              // Using StreamBuilder to fetch active batches
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('academic_years').snapshots(),
                builder: (context, snapshot) {
                  List<String> batches = [];
                  if (snapshot.hasData) {
                    batches = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                    batches.sort((a, b) => b.compareTo(a));
                  }
                  // Ensure current batch is in list if not fetched
                  if (_selectedBatch != null && !batches.contains(_selectedBatch)) {
                    batches.add(_selectedBatch!); // Keep existing even if inactive
                  }
                  
                  return DropdownButtonFormField<String>(
                    value: batches.contains(_selectedBatch) ? _selectedBatch : null,
                    decoration: const InputDecoration(labelText: "Batch", border: OutlineInputBorder()),
                    items: batches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                    onChanged: (val) => setState(() => _selectedBatch = val),
                  );
                },
              ),
              const SizedBox(height: 15),

              // QUOTA
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('quotas').orderBy('name').snapshots(),
                builder: (context, snapshot) {
                  List<String> quotas = [];
                  if (snapshot.hasData) {
                    quotas = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                  }

                  return DropdownButtonFormField<String>(
                    value: quotas.contains(_selectedQuota) ? _selectedQuota : null,
                    decoration: const InputDecoration(labelText: "Quota", border: OutlineInputBorder()),
                    items: quotas.map((q) => DropdownMenuItem(value: q, child: Text(q))).toList(),
                    onChanged: (val) => setState(() => _selectedQuota = val),
                  );
                }
              ),
              const SizedBox(height: 15),

              // TYPE
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: const InputDecoration(labelText: "Student Type", border: OutlineInputBorder()),
                items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t.toUpperCase().replaceAll("_", " ")))).toList(),
                onChanged: (val) => setState(() => _selectedType = val),
              ),
              const SizedBox(height: 15),

              // Bus Place (Conditional)
              if (_selectedType == 'bus_user')
                TextFormField(
                  initialValue: _busPlace,
                  decoration: const InputDecoration(labelText: "Bus Place (Route)", border: OutlineInputBorder()),
                  onChanged: (val) => _busPlace = val,
                ),
              
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateStudent,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Update Profile", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
