import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/error_handler.dart';

class RegisterScreen extends StatefulWidget {
  final Map<String, dynamic>? verifiedStudentData;
  final Map<String, dynamic>? verifiedStaffData; // NEW

  const RegisterScreen({super.key, this.verifiedStudentData, this.verifiedStaffData});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _regNoCtrl = TextEditingController();
  final _employeeIdCtrl = TextEditingController(); 
  final _parentPhoneCtrl = TextEditingController(); // NEW
  
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
    
    // Handle Verified Data
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
    } else if (widget.verifiedStaffData != null) { // NEW: Staff Handling
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
            // Only set default if not already set (e.g. from verified data)
            if (_selectedBatch.isEmpty) {
              _selectedBatch = _activeBatches.first;
            } else if (!_activeBatches.contains(_selectedBatch)) {
               // If verified batch is not in active list, add it or handle error?
               // For now, let's just add it so dropdown doesn't crash
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

      // Call Auth Service
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: MediaQuery.of(context).size.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.indigo[800]!, Colors.indigo[400]!],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const Text(
                        "CREATE ACCOUNT",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Join the Digital No-Dues Portal",
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 32),
                      
                      // ROLE SELECTOR
                      const _SectionHeader(title: "Identity"),
                      // Disable Role Selection if verified
                      DropdownButtonFormField(
                        value: _selectedRole,
                        decoration: InputDecoration(
                          labelText: "Registering as",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.person_pin_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'student', child: Text('Student')),
                          DropdownMenuItem(value: 'staff', child: Text('Staff / HOD')),
                          // DropdownMenuItem(value: 'admin', child: Text('Admin')), // Removed per user request
                        ],
                        onChanged: _isVerified ? null : (val) => setState(() => _selectedRole = val.toString()),
                      ),
                      const SizedBox(height: 24),

                      // CONDITIONAL FIELDS
                      if (_selectedRole == 'student' || _selectedRole == 'staff') ...[
                        const _SectionHeader(title: "Academic Context"),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('departments').orderBy('name').snapshots(),
                          builder: (context, snapshot) {
                            List<String> depts = [];
                            if (snapshot.hasData) {
                              depts = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                            }
                            if (depts.isEmpty) depts = ['CSE', 'ECE', 'MECH', 'CIVIL']; 

                            return DropdownButtonFormField(
                              value: depts.contains(_selectedDept) ? _selectedDept : null,
                              decoration: InputDecoration(
                                labelText: "Department", 
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.account_balance_outlined),
                                filled: _isVerified, // Visually indicate locked
                                fillColor: _isVerified ? Colors.grey[200] : null,
                              ),
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
                            value: _selectedBatch,
                            decoration: InputDecoration(
                              labelText: "Batch", 
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.group_outlined),
                              filled: _isVerified && widget.verifiedStudentData!.containsKey('batch'),
                              fillColor: (_isVerified && widget.verifiedStudentData!.containsKey('batch')) ? Colors.grey[200] : null,
                            ),
                            items: _activeBatches.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                            onChanged: (_isVerified && widget.verifiedStudentData!.containsKey('batch')) ? null : (val) => setState(() => _selectedBatch = val.toString()),
                        ),
                        const SizedBox(height: 16),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('quotas').orderBy('name').snapshots(),
                          builder: (context, snapshot) {
                            List<String> quotas = [];
                            if (snapshot.hasData) {
                              quotas = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                            }
                            if (quotas.isEmpty) quotas = ['Management', 'Counseling'];

                            // Ensure default is valid or null
                            String? validQuota = quotas.contains(_selectedQuota) ? _selectedQuota : (quotas.isNotEmpty ? quotas.first : null);

                            bool lockQuota = _isVerified && widget.verifiedStudentData!.containsKey('quota');

                            return DropdownButtonFormField(
                              value: validQuota,
                              decoration: InputDecoration(
                                labelText: "Admission Quota",
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.assignment_ind_outlined),
                                filled: lockQuota,
                                fillColor: lockQuota ? Colors.grey[200] : null,
                              ),
                              items: quotas.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                              onChanged: lockQuota ? null : (val) => setState(() => _selectedQuota = val.toString()),
                              validator: (val) => val == null ? 'Please select a quota' : null,
                            );
                          }
                        ),

                        const SizedBox(height: 16),
                        
                        // Fix: Calculate lockType before using it in the list, or just inline the check
                        DropdownButtonFormField<String>(
                          value: _selectedStudentType,
                          decoration: InputDecoration(
                            labelText: "Type",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.directions_walk_outlined),
                            filled: _isVerified && widget.verifiedStudentData!.containsKey('type'),
                            fillColor: (_isVerified && widget.verifiedStudentData!.containsKey('type')) ? Colors.grey[200] : null,
                          ),
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
                              decoration: InputDecoration(
                                labelText: "Bus Route",
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.bus_alert_outlined),
                              ),
                              items: _availableBusPlaces.map((place) => DropdownMenuItem(value: place, child: Text(place))).toList(),
                              onChanged: (val) => setState(() => _selectedBusPlace = val),
                              validator: (v) => v == null ? "Please select your bus route" : null,
                            )
                        ],
                        const SizedBox(height: 24),
                      ],

                      const _SectionHeader(title: "Personal Credentials"),
                      TextFormField(
                        controller: _nameCtrl,
                        readOnly: _isVerified, // LOCK IF VERIFIED
                        decoration: InputDecoration(
                           labelText: "Full Name", 
                           border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), 
                           prefixIcon: const Icon(Icons.person_outline),
                           filled: _isVerified,
                           fillColor: _isVerified ? Colors.grey[200] : null,
                        ),
                        validator: (v) => v!.isEmpty ? "Required" : null,
                      ),
                      const SizedBox(height: 16),
                      if (_selectedRole == 'student') 
                        TextFormField(
                          controller: _regNoCtrl,
                          readOnly: _isVerified, 
                          decoration: InputDecoration(
                             labelText: "Register Number", 
                             border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), 
                             prefixIcon: const Icon(Icons.numbers_outlined),
                             filled: _isVerified,
                             fillColor: _isVerified ? Colors.grey[200] : null,
                          ),
                          validator: (v) => v!.isEmpty ? "Required" : null,
                        )
                      else
                        TextFormField(
                          controller: _employeeIdCtrl,
                          readOnly: _isVerified, // Lock if verified
                          decoration: InputDecoration(
                            labelText: "Employee ID", 
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), 
                            prefixIcon: const Icon(Icons.badge_outlined),
                            filled: _isVerified,
                            fillColor: _isVerified ? Colors.grey[200] : null,
                          ),
                          validator: (v) => v!.isEmpty ? "Required" : null,
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: InputDecoration(labelText: "Email address", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.email_outlined)),
                        validator: Validators.validateEmail,
                      ),
                      if (_selectedRole == 'student') ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _parentPhoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: "Parent's Phone Number", 
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), 
                            prefixIcon: const Icon(Icons.family_restroom_outlined),
                            helperText: "For fee updates & alerts via SMS",
                          ),
                          validator: (v) => (v == null || v.length != 10) ? "Enter valid 10-digit number" : null,
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscurePassword,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: InputDecoration(
                          labelText: "Password",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 20, color: Colors.grey[600],
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: Validators.validatePassword,
                      ),
                      const SizedBox(height: 32),
                      
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleRegister,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoading 
                            ? const CircularProgressIndicator(color: Colors.white) 
                            : Text("CREATE ${_selectedRole.toUpperCase()} ACCOUNT", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Already have an account? Sign In"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo, letterSpacing: 1.1)),
          const SizedBox(width: 8),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
