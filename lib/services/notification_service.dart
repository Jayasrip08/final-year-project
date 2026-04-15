import 'web_notification_helper_stub.dart'
    if (dart.library.js) 'web_notification_helper_web.dart';
import 'web_badge_stub.dart'
    if (dart.library.html) 'web_badge_web.dart';

// determine whether we should run mobile badge logic (android/windows)
import 'platform_stub.dart'
    if (dart.library.io) 'platform_mobile.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app_icon_badge/flutter_app_icon_badge.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart'; // Import to access messengerKey and navigatorKey
import '../screens/notifications_screen.dart';
import '../screens/student/semester_detail_screen.dart';// Import for navigation targets

/// Top-level function for background message handling
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message received: ${message.notification?.title}');
  try {
    await NotificationService().updateAppBadge();
  } catch (e) {
    debugPrint('Error updating badge from background handler: $e');
  }
}

/// Notification Service for managing FCM notifications
class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  /// Initialize FCM and request permissions
  Future<void> initialize() async {
    try {
      if (!kIsWeb) {
        if (isAndroidOrWindows && !kIsWeb) {
          const AndroidNotificationChannel channel = AndroidNotificationChannel(
            'high_importance_channel',
            'High Importance Notifications',
            description: 'This channel is used for important notifications.',
            importance: Importance.max,
          );

          const AndroidNotificationChannel badgeChannel = AndroidNotificationChannel(
            'badge_channel',
            'Notification Count',
            description: 'Shows your unread notification count.',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          );

          final androidPlugin = _localNotifications
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
          await androidPlugin?.createNotificationChannel(channel);
          await androidPlugin?.createNotificationChannel(badgeChannel);
        }

        const AndroidInitializationSettings initializationSettingsAndroid =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        const InitializationSettings initializationSettings = InitializationSettings(
          android: initializationSettingsAndroid,
        );
        
        await _localNotifications.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (details) {
            // Handle tap on local notification
            _handleNotificationTap(RemoteMessage(data: {})); 
          },
        );

        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }
      } else {
        requestWebNotificationPermission();
      }

      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized || 
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        
        String? token;
        if (kIsWeb) {
          token = await _messaging.getToken(
            vapidKey: "BPEWU6G83xz5r5NZnJ1-XXcyr54bPj7RqknxvIox9JBaR1Dg9T-WsH5j-5QtzJO_vCYkNSMLuZkH3bgvyxnrIcM",
          );
        } else {
          token = await _messaging.getToken();
        }

        if (token != null) {
          await saveFCMToken(token);
        }

        _messaging.onTokenRefresh.listen(saveFCMToken);
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

        RemoteMessage? initialMessage = await _messaging.getInitialMessage();
        if (initialMessage != null) {
          _handleNotificationTap(initialMessage);
        }
      }
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  /// Save FCM token to Firestore
  Future<void> saveFCMToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  /// Handle foreground messages (when app is open)
  void _handleForegroundMessage(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && kIsWeb) {
      showWebNotification(notification.title ?? 'Notification', notification.body ?? '');
    }

    if (notification != null && !kIsWeb && isAndroidOrWindows) {
      final badgeCount = await getUnreadNotificationCount();
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            channelDescription: 'This channel is used for important notifications.',
            icon: android?.smallIcon ?? '@mipmap/ic_launcher',
            importance: Importance.max,
            priority: Priority.high,
            number: badgeCount,
          ),
        ),
      );
    }

    if (notification != null) {
      showInAppNotification(notification.title ?? 'Notification', notification.body ?? '');
    }

    try { await updateAppBadge(); } catch (_) {}

    if (message.data.containsKey('notificationId')) {
      _markNotificationAsReceived(message);
    }
  }

  static const int _badgeNotifId = 99998;

  Future<void> updateAppBadge() async {
    final count = await getUnreadNotificationCount();
    if (kIsWeb) { setWebBadge(count); return; }
    if (!isAndroidOrWindows) return;

    try {
      if (count == 0) { await clearAppBadge(); return; }
      try { await FlutterAppIconBadge.updateBadge(count); } catch (_) {}
      await _localNotifications.show(
        _badgeNotifId, '', '',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'badge_channel', 'Notification Count',
            importance: Importance.low,
            priority: Priority.low,
            showWhen: false,
            number: count,
          ),
        ),
      );
    } catch (e) { debugPrint('Error updating app badge: $e'); }
  }

  Future<void> clearAppBadge() async {
    if (kIsWeb) { clearWebBadge(); return; }
    if (!isAndroidOrWindows) return;
    try { await FlutterAppIconBadge.removeBadge(); } catch (_) {}
    try { await _localNotifications.cancel(_badgeNotifId); } catch (_) {}
  }

  bool _launchNotifShown = false;

  Future<void> showLaunchNotification() async {
    if (kIsWeb || !isAndroidOrWindows || _launchNotifShown) return;
    final unread = await getUnreadNotificationCount();
    if (unread == 0) { _launchNotifShown = true; return; }

    try {
      await _localNotifications.show(
        0, 'A-DACS', 'Welcome back! You have notifications waiting.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel', 'High Importance Notifications',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) { debugPrint('Error showing launch notification: $e'); }
    _launchNotifShown = true;
  }

  /// Handle notification tap with specific routing logic
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tapped with data: ${message.data}');
    
    final String? type = message.data['type'];
    final String? semester = message.data['semester'];

    // Specific Routing Logic
    if (type == 'fee_update' || type == 'payment_verified') {
      // If the notification is about a fee, go to Semester details
      if (semester != null) {
        _navigateToSemester(semester);
        return;
      }
    } 
    
    // Default fallback: Go to Notifications Screen
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  /// Helper for targeted navigation
  void _navigateToSemester(String semester) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Fetch user data needed for the SemesterDetailScreen
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => SemesterDetailScreen(
            userData: userDoc.data()!,
            semester: semester,
          ),
        ),
      );
    }
  }

  Future<void> _markNotificationAsReceived(RemoteMessage message) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && message.data.containsKey('notificationId')) {
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(message.data['notificationId'])
            .update({'received': true, 'receivedAt': FieldValue.serverTimestamp()});
      }
    } catch (e) { debugPrint('Error marking notification as received: $e'); }
  }

  static void showSuccess(String message) {
    messengerKey.currentState?.hideCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32), // Refined Emerald Green
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  static void showError(String message) {
    messengerKey.currentState?.hideCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: const Color(0xFFC62828), // Professional Deep Red
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  static void showInfo(String message) {
    messengerKey.currentState?.hideCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: const Color(0xFF1565C0), // Premium Blue
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  static void showInAppNotification(String title, String body) {
    messengerKey.currentState?.hideCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.indigo[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.amber,
          onPressed: () {
             navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
          },
        ),
        content: Text("$title: $body", style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<int> getUnreadNotificationCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final snapshot = await FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: user.uid)
            .where('read', isEqualTo: false)
            .count().get();
        return snapshot.count ?? 0;
      }
    } catch (e) { debugPrint('Error unread count: $e'); }
    return 0;
  }

  Stream<int> getUnreadCountStream() {
    return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(0);
      return FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('read', isEqualTo: false)
          .snapshots()
          .map((snapshot) => snapshot.docs.length);
    });
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true, 'readAt': FieldValue.serverTimestamp()});
      await updateAppBadge();
    } catch (e) { debugPrint('Error reading notification: $e'); }
  }

  Future<void> deleteFCMToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'fcmToken': FieldValue.delete()});
        await _messaging.deleteToken();
      }
    } catch (e) { debugPrint('Error deleting token: $e'); }
  }
}