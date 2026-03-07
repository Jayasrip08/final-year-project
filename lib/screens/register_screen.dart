import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/error_handler.dart';

class RegisterScreen extends StatefulWidget {
  final Map<String, dynamic>? verifiedStudentData;
  final Map<String, dynamic>? verifiedStaffData; 

  const RegisterScreen({super.key, this.verifiedStudentData, this.verifiedStaffData});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // CUSTOM PROJECT COLOR
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);
  
  // Controllers
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _regNoCtrl = TextEditingController();
  final _employeeIdCtrl = TextEditingController(); 
  final _parentPhoneCtrl = TextEditingController();
  
  // Dropdown Selections
  String _selectedRole = 'student'; 
  String _selectedDept = 'CSE';
  String _selectedBatch = ''; 
  String _selectedQuota = 'Management'; 
  String _selectedStudentType = 'day_scholar'; 
  String? _selectedBusPlace; 
  List<String> _availableBusPlaces = []; 
  bool _isLoading = false;
  bool _obscurePassword = true;
  List<String> _activeBatches = []; 
  bool _isVerified = false;

  @override
  void initState() {
    super.initState();
    _loadActiveBatches();
    
    if (widget.verifiedStudentData != null) {
      _isVerified = true;
      _selectedRole = 'student';
      _nameCtrl.text = widget.verifiedStudentData!['name'] ?? '';
      _regNoCtrl.text = widget.verifiedStudentData!['regNo'] ?? '';
      _selectedDept = widget.verifiedStudentData!['dept'] ?? 'CSE';
      
      if (widget.verifiedStudentData!.containsKey('quota')) {
         _selectedQuota = widget.verifiedStudentData!['quota']; 
      }
      if (widget.verifiedStudentData!.containsKey('type')) {
         String type = widget.verifiedStudentData!['type'].toString().toLowerCase().replaceAll(' ', '_');
         if (['day_scholar', 'hosteller', 'bus_user'].contains(type)) {
            _selectedStudentType = type;
         }
      }
      if (widget.verifiedStudentData!.containsKey('batch')) {
         _selectedBatch = widget.verifiedStudentData!['batch'];
      }
    } else if (widget.verifiedStaffData != null) {
      _isVerified = true;
      _selectedRole = 'staff'; 
      _nameCtrl.text = widget.verifiedStaffData!['name'] ?? '';
      _employeeIdCtrl.text = widget.verifiedStaffData!['employeeId'] ?? '';
      _selectedDept = widget.verifiedStaffData!['dept'] ?? 'CSE';
    }
  }

  Future<void> _loadActiveBatches() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('academic_years')
          .where('isActive', isEqualTo: true)
          .get();
      
      if (mounted) {
        setState(() {
          _activeBatches = snapshot.docs.map((doc) => doc['name'] as String).toList();
          if (_activeBatches.isNotEmpty) {
            if (_selectedBatch.isEmpty) {
              _selectedBatch = _activeBatches.first;
            } else if (!_activeBatches.contains(_selectedBatch)) {
               _activeBatches.add(_selectedBatch);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading batches: $e')),
        );
      }
    }
  }

  Future<void> _loadBusPlaces() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('fee_structures')
          .where('isActive', isEqualTo: true)
          .get();
      
      final docs = snapshot.docs.toList();
      docs.sort((a, b) {
        final aTime = (a.data()['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final bTime = (b.data()['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });
      
      List<String> foundPlaces = [];
      for (var doc in docs) {
        final data = doc.data();
        final components = data['components'] as Map<String, dynamic>?;
        if (components != null && components['Bus Fee'] is Map) {
          final busFeeMap = components['Bus Fee'] as Map<String, dynamic>;
          if (busFeeMap.isNotEmpty) {
            foundPlaces = busFeeMap.keys.toList().cast<String>();
            break; 
          }
        }
      }

      if (mounted) {
        setState(() {
          _availableBusPlaces = foundPlaces;
          if (_availableBusPlaces.isNotEmpty) {
            _selectedBusPlace = _availableBusPlaces.first;
          } else {
             _selectedBusPlace = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, 'Error loading bus routes. Please try again.');
      }
    }
  }

  void _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedRole == 'student' && _selectedBatch.isEmpty) {
        setState(() => _isLoading = false);
        ErrorHandler.showWarning(context,
            'Cannot register student without an active batch. Please contact admin.');
        return;
      }

      setState(() => _isLoading = true);

      String? error = await AuthService().registerUser(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        role: _selectedRole, 
        regNo: _selectedRole == 'student' ? _regNoCtrl.text.trim() : null,
        dept: (_selectedRole == 'student' || _selectedRole == 'staff') ? _selectedDept : null,
        quotaCategory: _selectedRole == 'student' ? _selectedQuota : null,
        employeeId: (_selectedRole == 'staff' || _selectedRole == 'admin') ? _employeeIdCtrl.text.trim() : null,
        batch: _selectedRole == 'student' ? _selectedBatch : null, 
        studentType: _selectedRole == 'student' ? _selectedStudentType : null, 
        busPlace: _selectedRole == 'student' && _selectedStudentType == 'bus_user' ? _selectedBusPlace : null, 
        phone: _selectedRole == 'student' 
            ? (widget.verifiedStudentData?['phone'] as String?) 
            : (widget.verifiedStaffData?['phone'] as String?),
        parentPhoneNumber: _selectedRole == 'student' 
            ? (_parentPhoneCtrl.text.trim().startsWith('+') 
                ? _parentPhoneCtrl.text.trim() 
                : '+91${_parentPhoneCtrl.text.trim()}') 
            : null,
        isApproved: _isVerified,
      );

      setState(() => _isLoading = false);

      if (error == null) {
        if (mounted) {
          String message = (_selectedRole == 'admin' || _isVerified)
              ? 'Registration successful! Please sign in.'
              : 'Registration successful! Your account is pending admin approval.';
          ErrorHandler.showSuccess(context, message,
              duration: const Duration(seconds: 5));
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        if (mounted) ErrorHandler.showError(context, error);
      }
    }
  }

  InputDecoration _customDecoration(String label, IconData icon, {bool locked = false}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: locked ? Colors.grey : customRed, size: 20),
      filled: locked,
      fillColor: locked ? Colors.grey[100] : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: customRed, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // CLEAN WHITE BACKGROUND
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: customRed),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              // HEADER LOGO/TEXT
              Icon(Icons.person_add_rounded, size: 60, color: customRed),
              const SizedBox(height: 16),
              Text(
                "CREATE ACCOUNT",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: customRed,
                  letterSpacing: 1.5,
                ),
              ),
              const Text(
                "Join the Digital No-Dues Portal",
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // IDENTITY SECTION
                    _SectionHeader(title: "Identity", color: customRed),
                    DropdownButtonFormField(
                      value: _selectedRole,
                      decoration: _customDecoration("Registering as", Icons.person_pin_outlined, locked: _isVerified),
                      items: const [
                        DropdownMenuItem(value: 'student', child: Text('Student')),
                        DropdownMenuItem(value: 'staff', child: Text('Staff / HOD')),
                      ],
                      onChanged: _isVerified ? null : (val) => setState(() => _selectedRole = val.toString()),
                    ),
                    const SizedBox(height: 24),

                    // ACADEMIC SECTION
                    if (_selectedRole == 'student' || _selectedRole == 'staff') ...[
                      _SectionHeader(title: "Academic Context", color: customRed),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('departments').orderBy('name').snapshots(),
                        builder: (context, snapshot) {
                          List<String> depts = snapshot.hasData 
                            ? snapshot.data!.docs.map((d) => d['name'] as String).toList() 
                            : ['CSE', 'ECE', 'MECH', 'CIVIL']; 

                          return DropdownButtonFormField(
                            value: depts.contains(_selectedDept) ? _selectedDept : null,
                            decoration: _customDecoration("Department", Icons.account_balance_outlined, locked: _isVerified),
                            items: depts.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                            onChanged: _isVerified ? null : (val) => setState(() => _selectedDept = val.toString()),
                            validator: (val) => val == null ? 'Please select a department' : null,
                          );
                        }
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_selectedRole == 'student') ...[
                      DropdownButtonFormField(
                          value: _selectedBatch.isNotEmpty ? _selectedBatch : null,
                          decoration: _customDecoration("Batch", Icons.group_outlined, 
                              locked: _isVerified && widget.verifiedStudentData!.containsKey('batch')),
                          items: _activeBatches.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (_isVerified && widget.verifiedStudentData!.containsKey('batch')) ? null : (val) => setState(() => _selectedBatch = val.toString()),
                      ),
                      const SizedBox(height: 16),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('quotas').orderBy('name').snapshots(),
                        builder: (context, snapshot) {
                          List<String> quotas = snapshot.hasData 
                            ? snapshot.data!.docs.map((d) => d['name'] as String).toList() 
                            : ['Management', 'Counseling'];

                          String? validQuota = quotas.contains(_selectedQuota) ? _selectedQuota : (quotas.isNotEmpty ? quotas.first : null);
                          bool lockQuota = _isVerified && widget.verifiedStudentData!.containsKey('quota');

                          return DropdownButtonFormField(
                            value: validQuota,
                            decoration: _customDecoration("Admission Quota", Icons.assignment_ind_outlined, locked: lockQuota),
                            items: quotas.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                            onChanged: lockQuota ? null : (val) => setState(() => _selectedQuota = val.toString()),
                            validator: (val) => val == null ? 'Please select a quota' : null,
                          );
                        }
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedStudentType,
                        decoration: _customDecoration("Type", Icons.directions_walk_outlined, 
                            locked: _isVerified && widget.verifiedStudentData!.containsKey('type')),
                        items: const [
                          DropdownMenuItem(value: 'day_scholar', child: Text('Day Scholar')),
                          DropdownMenuItem(value: 'hosteller', child: Text('Hosteller')),
                          DropdownMenuItem(value: 'bus_user', child: Text('Bus User')),
                        ],
                        onChanged: (_isVerified && widget.verifiedStudentData!.containsKey('type')) ? null : (val) {
                          setState(() {
                            _selectedStudentType = val!;
                            if (val == 'bus_user') _loadBusPlaces();
                          });
                        },
                      ),
                      if (_selectedStudentType == 'bus_user') ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                            value: _selectedBusPlace,
                            decoration: _customDecoration("Bus Route", Icons.bus_alert_outlined),
                            items: _availableBusPlaces.map((place) => DropdownMenuItem(value: place, child: Text(place))).toList(),
                            onChanged: (val) => setState(() => _selectedBusPlace = val),
                            validator: (v) => v == null ? "Please select your bus route" : null,
                          )
                      ],
                      const SizedBox(height: 24),
                    ],

                    // PERSONAL CREDENTIALS SECTION
                    _SectionHeader(title: "Personal Credentials", color: customRed),
                    TextFormField(
                      controller: _nameCtrl,
                      readOnly: _isVerified,
                      decoration: _customDecoration("Full Name", Icons.person_outline, locked: _isVerified),
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    ),
                    const SizedBox(height: 16),
                    if (_selectedRole == 'student') 
                      TextFormField(
                        controller: _regNoCtrl,
                        readOnly: _isVerified, 
                        decoration: _customDecoration("Register Number", Icons.numbers_outlined, locked: _isVerified),
                        validator: (v) => v!.isEmpty ? "Required" : null,
                      )
                    else
                      TextFormField(
                        controller: _employeeIdCtrl,
                        readOnly: _isVerified,
                        decoration: _customDecoration("Employee ID", Icons.badge_outlined, locked: _isVerified),
                        validator: (v) => v!.isEmpty ? "Required" : null,
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _customDecoration("Email Address", Icons.email_outlined),
                      // validator: Validators.validateEmail, // Logic remains the same
                    ),
                    if (_selectedRole == 'student') ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _parentPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: _customDecoration("Parent's Phone Number", Icons.family_restroom_outlined).copyWith(
                          helperText: "For fee updates & alerts via SMS",
                        ),
                        validator: (v) => (v == null || v.length != 10) ? "Enter valid 10-digit number" : null,
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscurePassword,
                      decoration: _customDecoration("Password", Icons.lock_outline).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 20, color: Colors.grey[600],
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      // validator: Validators.validatePassword, // Logic remains same
                    ),
                    const SizedBox(height: 40),
                    
                    // SUBMIT BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleRegister,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: customRed,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading 
                          ? const CircularProgressIndicator(color: Colors.white) 
                          : Text(
                              "CREATE ${_selectedRole.toUpperCase()} ACCOUNT", 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.1)
                            ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.grey, fontSize: 14),
                          children: [
                            const TextSpan(text: "Already have an account? "),
                            TextSpan(text: "Sign In", style: TextStyle(color: customRed, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(), 
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color, letterSpacing: 1.2)
          ),
          const SizedBox(width: 12),
          const Expanded(child: Divider(thickness: 1)),
        ],
      ),
    );
  }
}