import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// ErrorHandler – Rich snackbars, dialogs, retry logic
// ─────────────────────────────────────────────────────────────────────────────
class ErrorHandler {
  // ── Snackbars ───────────────────────────────────────────────────────────────

  static void showError(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
    Duration duration = const Duration(seconds: 5),
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(14),
          backgroundColor: Colors.red.shade700,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: duration,
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(message,
                      style: const TextStyle(color: Colors.white))),
            ],
          ),
          action: onRetry != null
              ? SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.amber,
                  onPressed: onRetry,
                )
              : null,
        ),
      );
  }

  static void showSuccess(BuildContext context, String message,
      {Duration duration = const Duration(seconds: 3)}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(14),
          backgroundColor: Colors.green.shade700,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: duration,
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(message,
                      style: const TextStyle(color: Colors.white))),
            ],
          ),
        ),
      );
  }

  static void showWarning(BuildContext context, String message,
      {Duration duration = const Duration(seconds: 4)}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(14),
          backgroundColor: Colors.orange.shade700,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: duration,
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(message,
                      style: const TextStyle(color: Colors.white))),
            ],
          ),
        ),
      );
  }

  static void showInfo(BuildContext context, String message,
      {Duration duration = const Duration(seconds: 3)}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(14),
          backgroundColor: Colors.blueGrey.shade700,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: duration,
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(message,
                      style: const TextStyle(color: Colors.white))),
            ],
          ),
        ),
      );
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────────

  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    Color confirmColor = Colors.red,
    IconData icon = Icons.warning_amber_rounded,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(icon, color: confirmColor, size: 24),
          const SizedBox(width: 10),
          Text(title),
        ]),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel,
                style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static void showLoadingDialog(BuildContext context, {String? message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                  child: Text(message ?? 'Please wait...',
                      style: const TextStyle(fontSize: 15))),
            ],
          ),
        ),
      ),
    );
  }

  static void hideLoadingDialog(BuildContext context) {
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  // ── Firebase error messages ─────────────────────────────────────────────────

  static String getFirebaseErrorMessage(dynamic error) {
    // Auth errors
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No account found with this email.';
        case 'wrong-password':
          return 'Incorrect password. Please try again.';
        case 'invalid-credential':
          return 'Invalid email or password. Please try again.';
        case 'email-already-in-use':
          return 'An account already exists with this email.';
        case 'weak-password':
          return 'Password is too weak. Use at least 6 characters.';
        case 'too-many-requests':
          return 'Too many failed attempts. Please wait a moment and try again.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        case 'user-disabled':
          return 'This account has been disabled. Contact admin.';
        default:
          return error.message ?? 'Authentication failed.';
      }
    }

    // Firestore errors
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You don\'t have permission to perform this action.';
        case 'not-found':
          return 'The requested data was not found.';
        case 'already-exists':
          return 'This record already exists.';
        case 'unavailable':
          return 'Service temporarily unavailable. Please try again.';
        case 'deadline-exceeded':
          return 'Request timed out. Please check your connection.';
        case 'cancelled':
          return 'Operation was cancelled.';
        default:
          return error.message ?? 'A database error occurred.';
      }
    }

    if (error is SocketException) {
      return 'No internet connection. Please check your network.';
    }

    final str = error.toString();
    // Strip "Exception:" prefix for cleaner messages
    return str.replaceAll('Exception: ', '').replaceAll('Exception:', '').trim();
  }

  // ── File upload with retry ───────────────────────────────────────────────────

  static Future<String?> uploadFileWithRetry({
    required File file,
    required String path,
    required BuildContext context,
    int maxRetries = 3,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final ref = FirebaseStorage.instance.ref().child(path);
        await ref.putFile(file);
        return await ref.getDownloadURL();
      } catch (e) {
        if (attempt == maxRetries) {
          if (context.mounted) {
            showError(context,
                'Upload failed after $maxRetries attempts. Please try again.',
                onRetry: null);
          }
          return null;
        }
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    return null;
  }

  // ── Operation with retry ────────────────────────────────────────────────────

  static Future<T?> executeWithRetry<T>({
    required Future<T> Function() operation,
    required BuildContext context,
    int maxRetries = 3,
    String? errorMessage,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        if (attempt == maxRetries) {
          if (context.mounted) {
            showError(context, errorMessage ?? getFirebaseErrorMessage(e));
          }
          return null;
        }
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    return null;
  }

  // ── Duplicate payment check ─────────────────────────────────────────────────

  static Future<bool> checkDuplicatePayment({
    required String studentId,
    required String transactionId,
  }) async {
    try {
      final existing = await FirebaseFirestore.instance
          .collection('payments')
          .where('studentId', isEqualTo: studentId)
          .where('transactionId', isEqualTo: transactionId)
          .limit(1)
          .get();
      return existing.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking duplicate payment: $e');
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Validators – All input validation
// ─────────────────────────────────────────────────────────────────────────────
class Validators {
  static String? validateEmail(String? v) {
    if (v == null || v.isEmpty) return 'Email is required';
    if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Must contain at least 1 uppercase letter';
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\\/~`]').hasMatch(v)) {
      return 'Must contain at least 1 special character (e.g. @, #, !)';
    }
    return null;
  }

  static String? validateName(String? v) {
    if (v == null || v.isEmpty) return 'Name is required';
    if (v.length < 2) return 'Name must be at least 2 characters';
    if (!RegExp(r'^[a-zA-Z\s.]+$').hasMatch(v)) {
      return 'Name can only contain letters and spaces';
    }
    return null;
  }

  static String? validateRegNo(String? v) {
    if (v == null || v.isEmpty) return 'Registration number is required';
    if (v.length < 5) return 'Enter a valid registration number';
    return null;
  }

  static String? validateAmount(String? v) {
    if (v == null || v.isEmpty) return 'Amount is required';
    final amount = double.tryParse(v);
    if (amount == null || amount <= 0) return 'Enter a valid amount';
    if (amount > 1000000) return 'Amount seems too large. Please verify.';
    return null;
  }

  static String? validateTransactionId(String? v) {
    if (v == null || v.isEmpty) return 'Transaction ID is required';
    if (v.length < 6) return 'Transaction ID must be at least 6 characters';
    return null;
  }

  static String? validatePhone(String? v) {
    if (v == null || v.isEmpty) return null; // optional
    if (!RegExp(r'^[0-9]{10}$').hasMatch(v)) {
      return 'Enter a valid 10-digit phone number';
    }
    return null;
  }

  static String? validateRequired(String? v, String fieldName) {
    if (v == null || v.isEmpty) return '$fieldName is required';
    return null;
  }

  static String? validateDropdown(dynamic v, String fieldName) {
    if (v == null) return 'Please select $fieldName';
    return null;
  }

  static String? validateDate(DateTime? v, String fieldName) {
    if (v == null) return '$fieldName is required';
    return null;
  }

  static String? validateFutureDate(DateTime? v, String fieldName) {
    if (v == null) return '$fieldName is required';
    if (v.isBefore(DateTime.now())) return '$fieldName must be in the future';
    return null;
  }

  static String? validateDateRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return 'Both dates are required';
    if (end.isBefore(start)) return 'End date must be after start date';
    return null;
  }
}
