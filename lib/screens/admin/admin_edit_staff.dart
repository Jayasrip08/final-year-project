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
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  
  String? _selectedDept;
  String? _selectedRole;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.staffData['name']);
    _emailCtrl = TextEditingController(text: widget.staffData['email']);
    _phoneCtrl = TextEditingController(text: widget.staffData['phone'] ?? '');
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
      appBar: AppBar(
        title: const Text("Edit Staff Profile"),
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
                  // Full Name
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
                  // Email (read-only)
                  TextFormField(
                    controller: _emailCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: "Email",
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
                      fillColor: Colors.grey[100],
                      prefixIcon: Icon(Icons.email_outlined, color: customRed),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Phone Number
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: InputDecoration(
                      labelText: "Phone Number",
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
                      prefixIcon: Icon(Icons.phone_outlined, color: customRed),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.isEmpty || v.length < 10) ? "Enter valid phone number" : null,
                  ),
                  const SizedBox(height: 16),
                  
                  // Department Dropdown
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
                  const SizedBox(height: 24),
                  // Update Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _updateStaff,
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