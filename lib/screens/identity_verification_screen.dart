import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'register_screen.dart';

class IdentityVerificationScreen extends StatefulWidget {
  final String userType; // 'student' or 'staff'
  const IdentityVerificationScreen({super.key, this.userType = 'student'});

  @override
  State<IdentityVerificationScreen> createState() => _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState extends State<IdentityVerificationScreen> {
  final _idCtrl = TextEditingController(); 
  final _otpCtrl = TextEditingController();
  
  // CUSTOM PROJECT COLOR
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);
  
  bool _isLoading = false;
  bool _otpSent = false;
  String? _verificationId;
  int? _resendToken;
  
  Map<String, dynamic>? _userData;
  String _maskedPhone = "";

  String get _idLabel => widget.userType == 'student' ? "Register Number" : "Employee ID";
  String get _collectionName => widget.userType == 'student' ? 'student_master_list' : 'staff_master_list';

  void _lookupUser() async {
    if (_idCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Please enter $_idLabel")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance.collection(_collectionName).doc(_idCtrl.text.trim()).get();
      
      if (!doc.exists) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("$_idLabel not found in college records. Please contact Admin."), backgroundColor: customRed)
           );
        }
        setState(() => _isLoading = false);
        return;
      }

      final data = doc.data()!;
      if (data['isRegistered'] == true) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text("This user is already registered. Please Login."), backgroundColor: Colors.orange)
           );
        }
        setState(() => _isLoading = false);
        return;
      }

      _userData = data;
      String phone = data['phone'] ?? '';
      
      if (phone.length > 4) {
        _maskedPhone = phone.replaceRange(0, phone.length - 4, '*' * (phone.length - 4));
      } else {
        _maskedPhone = "****";
      }

      _sendOTP(phone);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      setState(() => _isLoading = false);
    }
  }

  void _sendOTP(String phoneNumber) async {
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Verification Failed: ${e.message}")));
          setState(() => _isLoading = false);
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _otpSent = true;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("OTP Sent to your registered mobile number")));
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
        forceResendingToken: _resendToken,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error sending OTP: $e")));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpCtrl.text.isEmpty || _verificationId == null) return;

    setState(() => _isLoading = true);
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpCtrl.text.trim()
      );
      
      await _signInWithCredential(credential);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid OTP: $e")));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      await FirebaseAuth.instance.signOut(); 
      
      if (mounted) {
         Navigator.pushReplacement(
           context, 
           MaterialPageRoute(
             builder: (_) => RegisterScreen(
               verifiedStudentData: widget.userType == 'student' ? _userData : null,
               verifiedStaffData: widget.userType == 'staff' ? _userData : null,
             )
           )
         );
      }
    } catch (e) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("OTP Error: $e")));
         setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: customRed),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "${widget.userType == 'student' ? 'Student' : 'Staff'} Verification",
          style: TextStyle(color: customRed, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // THEME ICON
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: customRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(_otpSent ? Icons.mark_email_read_rounded : Icons.verified_user_rounded, size: 60, color: customRed),
              ),
              const SizedBox(height: 30),
              Text(
                _otpSent ? "Verify OTP" : "Identity Check", 
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87)
              ),
              const SizedBox(height: 12),
              Text(
                _otpSent 
                  ? "We've sent a 6-digit code to your registered mobile number ending in $_maskedPhone"
                  : "Please enter your official $_idLabel. We will verify this against the college master records.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 40),
              
              if (!_otpSent) ...[
                // ID INPUT
                TextField(
                  controller: _idCtrl,
                  keyboardType: TextInputType.text,
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  decoration: _inputDecoration(
                    label: _idLabel,
                    icon: Icons.badge_outlined,
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _lookupUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: customRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text("VERIFY & SEND OTP", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ] else ...[
                // OTP INPUT
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
                  maxLength: 6,
                  decoration: _inputDecoration(
                    label: "6-Digit OTP",
                    icon: Icons.lock_clock_outlined,
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: customRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text("CONFIRM & REGISTER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 15),
                TextButton(
                  onPressed: () => setState(() {
                    _otpSent = false;
                    _isLoading = false;
                    _otpCtrl.clear();
                  }),
                  child: Text(
                    "Change $_idLabel",
                    style: TextStyle(color: customRed, fontWeight: FontWeight.w600),
                  ),
                )
              ],
              const SizedBox(height: 40),
              // SECURITY NOTE
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: Colors.grey[400]),
                  const SizedBox(width: 8),
                  Text("Secure Identity Verification System", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: customRed),
      counterText: "", // Hide character counter
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: customRed, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );
  }
}