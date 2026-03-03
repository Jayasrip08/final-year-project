import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminEditStaff extends StatefulWidget {
  final Map<String, dynamic> staffData;
  final String staffId;

  const AdminEditStaff({super.key, required this.staffData, required this.staffId});

  @override
  State<AdminEditStaff> createState() => _AdminEditStaffState();
}

class _AdminEditStaffState extends State<AdminEditStaff> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl; // NEW
  
  String? _selectedDept;
  String? _selectedRole;

  bool _isLoading = false;


  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.staffData['name']);
    _emailCtrl = TextEditingController(text: widget.staffData['email']);
    _phoneCtrl = TextEditingController(text: widget.staffData['phone'] ?? ''); // NEW
    _selectedDept = widget.staffData['dept'];
    _selectedRole = widget.staffData['role'];
    _fetchMasterListPhone();
  }

  void _fetchMasterListPhone() async {
    String? empId = widget.staffData['employeeId'];
    if (empId != null && empId.isNotEmpty) {
      var doc = await FirebaseFirestore.instance.collection('staff_master_list').doc(empId).get();
      if (doc.exists && doc.data()?['phone'] != null) {
        if (mounted) {
          setState(() {
            _phoneCtrl.text = doc.data()!['phone'];
          });
        }
      }
    }
  }

  Future<void> _updateStaff() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final phone = _phoneCtrl.text.trim().startsWith('+') 
          ? _phoneCtrl.text.trim() 
          : '+91${_phoneCtrl.text.trim()}';

      await FirebaseFirestore.instance.collection('users').doc(widget.staffId).update({
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': phone,
        'dept': _selectedDept,
        'role': _selectedRole,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // SYNC WITH MASTER LIST
      String? empId = widget.staffData['employeeId'];
      if (empId != null && empId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('staff_master_list').doc(empId).update({
          'phone': phone,
          'name': _nameCtrl.text.trim(),
          'dept': _selectedDept,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Staff Profile Updated")));
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
      appBar: AppBar(title: const Text("Edit Staff Profile"), backgroundColor: Colors.indigo),
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
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder()),
                readOnly: true, // Email usually read-only as it's the auth key
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                  labelText: "Phone Number", 
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.isEmpty || v.length < 10) ? "Enter valid phone number" : null,
              ),
              const SizedBox(height: 15),
              
              // DEPT
              // DEPT
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('departments').orderBy('name').snapshots(),
                builder: (context, snapshot) {
                  List<String> depts = [];
                  if (snapshot.hasData) {
                    depts = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                  }
                  
                  return DropdownButtonFormField<String>(
                    value: depts.contains(_selectedDept) ? _selectedDept : null,
                    decoration: const InputDecoration(labelText: "Department", border: OutlineInputBorder()),
                    items: depts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (val) => setState(() => _selectedDept = val),
                  );
                }
              ),
              const SizedBox(height: 15),

              // ROLE (Read Only display or removed)
              // User requested to remove edit for role.
              // We can show it as read-only text or remove it. "dont show role in that" -> Removing.
              
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateStaff,
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
