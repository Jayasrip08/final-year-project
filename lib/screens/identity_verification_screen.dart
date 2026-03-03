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
  final _idCtrl = TextEditingController(); // Renamed from _regNoCtrl
  final _otpCtrl = TextEditingController();
  
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
             SnackBar(content: Text("$_idLabel not found in college records. Please contact Admin."), backgroundColor: Colors.red)
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
      
      // Mask Phone: +91 9876543210 -> +91 ******3210
      if (phone.length > 4) {
        _maskedPhone = phone.replaceRange(0, phone.length - 4, '*' * (phone.length - 4));
      } else {
        _maskedPhone = "****";
      }

      // Automatically trigger OTP
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
          // Auto-resolution on Android
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
      // NOTE: We don't want to actually sign in with Phone Auth because 
      // the user needs to create an EMAIL/PASSWORD account in the next step.
      // However, verifyPhoneNumber forces a sign-in credential.
      // We just validated they own the phone. 
      // We can proceed to Register Screen now.
      
      // But wait... verifyPhoneNumber is for AUTH. 
      // If we use signInWithCredential, it creates a Firebase User with phone provider.
      // We want to link this or just use it as a gatekeeper.
      
      // Strategy: 
      // 1. Authenticate with Phone.
      // 2. Get the UID? No, we just need proof.
      // 3. Navigate to Register Screen.
      // 4. In Register Screen, create Email/User.
      // 5. Link Phone Credential? Or just ignore it? 
      // If we ignore it, user has 2 accounts? Phone user and Email user. 
      // Better: Create Email User, then Link Phone Credential? 
      // OR: Just treat this step as "passed" and sign out the phone user immediately.
      
      // Let's sign in to verify the code is correct.
      // UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      // If successful, it means OTP was correct.
      
      // IMPORTANT: If we sign in here, the Auth State changes.
      // We should sign out immediately so Register Screen starts fresh.
      // BUT: We need to pass the "Verified" status.
      
      // Wait, we can't easily "Verify without Sign In" using the high-level SDK unless we link.
      // So yes, sign in, then sign out.
      
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
      appBar: AppBar(title: Text("${widget.userType == 'student' ? 'Student' : 'Staff'} Verification")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.security, size: 60, color: Colors.blue),
            const SizedBox(height: 20),
            Text(
              "${widget.userType == 'student' ? 'Student' : 'Staff'} Identity Verification", 
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 10),
            Text(
              _otpSent 
                ? "Enter the OTP sent to $_maskedPhone"
                : "Enter your $_idLabel to verify your identity against college records.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            
            if (!_otpSent) ...[
              TextField(
                controller: _idCtrl,
                decoration: InputDecoration(
                  labelText: _idLabel,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.numbers),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _lookupUser,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                  child: _isLoading 
                    ? const CircularProgressIndicator() 
                    : const Text("VERIFY & SEND OTP"),
                ),
              ),
            ] else ...[
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Enter OTP",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_clock),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOTP,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: Colors.green),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text("CONFIRM & REGISTER", style: TextStyle(color: Colors.white)),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _otpSent = false;
                  _isLoading = false;
                }),
                child: const Text("Change Register Number"),
              )
            ],
          ],
        ),
      ),
    );
  }
}
