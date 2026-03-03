import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Service to track student activity for optimal notification timing
class ActivityTracker with WidgetsBindingObserver {
  static final ActivityTracker _instance = ActivityTracker._internal();

  factory ActivityTracker() {
    return _instance;
  }

  ActivityTracker._internal();

  /// Initialize activity tracking
  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    recordActivity(); // Record initial activity
  }

  /// Clean up when done
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Record user activity timestamp
  Future<void> recordActivity() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'lastActiveAt': FieldValue.serverTimestamp(),
        });
        print('Activity recorded at ${DateTime.now()}');
      }
    } catch (e) {
      print('Error recording activity: $e');
    }
  }

  /// Called when app lifecycle state changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground
      recordActivity();
    }
  }
}
