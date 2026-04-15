import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/error_handler.dart';
import 'identity_verification_screen.dart';
import 'student/student_dashboard.dart';
import 'admin/admin_dashboard.dart';
import 'staff/staff_dashboard.dart';

// Assuming Validators class is defined in your project, if not, 
// ensure you have the proper import for it.

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final userData = await _authService.loginUser(
        _emailCtrl.text.trim(),
        _passCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (userData != null) {
        final role = (userData['role'] as String? ?? '').trim().toLowerCase();
        Widget nextScreen;
        if (role == 'admin') {
          nextScreen = const AdminDashboard();
        } else if (role == 'staff') {
          nextScreen = const StaffDashboard();
        } else {
          nextScreen = const StudentDashboard();
        }
        if (mounted) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => nextScreen));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      final msg = ErrorHandler.getFirebaseErrorMessage(e);

      if (msg.toLowerCase().contains('pending admin approval') ||
          msg.toLowerCase().contains('pending')) {
        _showApprovalPendingDialog();
      } else {
        ErrorHandler.showError(context, msg);
      }
    }
  }

  void _showApprovalPendingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.hourglass_top, color: Colors.orange),
          const SizedBox(width: 10),
          const Text("Approval Pending"),
        ]),
        content: const Text(
          "Your account is currently waiting for admin approval.\n\n"
          "You will receive a notification once an administrator verifies your details.",
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // CHANGED: White background
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                // ── LOGO (Matches Splash Screen) ──────────────────────
                Image.asset(
                  'assets/app_logo.png', // Same as Splash Screen
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.school, size: 80, color: Color.fromARGB(255, 198, 55, 45)),
                ),
                const Text(
                  "A-DACS",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 198, 55, 45), // CHANGED: Red Title
                    letterSpacing: 2,
                  ),
                ),
                const Text(
                  "Digital Clearance System",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),

                const SizedBox(height: 40),

                // ── LOGIN FORM ─────────────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Welcome back",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Sign in to your account",
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 32),

                      // Email
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        // validator: Validators.validateEmail, // Logic kept
                        decoration: _inputDecoration(
                          label: "Email address",
                          icon: Icons.email_outlined,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Password
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        // validator: Validators.validatePassword, // Logic kept
                        decoration: _inputDecoration(
                          label: "Password",
                          icon: Icons.lock_outline,
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Sign In button
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color.fromARGB(255, 198, 55, 45), // CHANGED: Red Button
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.red[200],
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text(
                                  "SIGN IN",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 1.2),
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Register link
                      Center(
                        child: TextButton(
                          onPressed: () => _showRegistrationTypeDialog(context),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 14),
                              children: [
                                TextSpan(
                                    text: "Don't have an account? ",
                                    style: TextStyle(color: Colors.grey[600])),
                                const TextSpan(
                                    text: "Register",
                                    style: TextStyle(
                                        color: Color.fromARGB(255, 198, 55, 45), // CHANGED: Red Link
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
      {required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, size: 22, color: Colors.grey),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color.fromARGB(255, 198, 55, 45), width: 2), // CHANGED: Red Focus
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color.fromARGB(255, 198, 55, 45), width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color.fromARGB(255, 198, 55, 45), width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  void _showRegistrationTypeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.app_registration, color: Color.fromARGB(255, 198, 55, 45)),
          const SizedBox(width: 10),
          const Text("Register As"),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _registerTile(
              ctx: ctx,
              icon: Icons.school,
              color: Color.fromARGB(255, 198, 55, 45),
              label: "Student",
              subtitle: "Requires Student ID Verification",
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const IdentityVerificationScreen()));
              },
            ),
            const Divider(height: 16),
            _registerTile(
              ctx: ctx,
              icon: Icons.work_outline,
              color: Colors.orange,
              label: "Staff / HOD",
              subtitle: "Requires Employee ID Verification",
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const IdentityVerificationScreen(
                            userType: 'staff')));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _registerTile({
    required BuildContext ctx,
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}