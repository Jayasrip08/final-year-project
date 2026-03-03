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

/// Top-level function for background message handling
/// This must be a top-level function (not inside a class)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // This runs in its own isolate when the app is terminated or in the
  // background.  We don't have access to most of the app state, but the
  // one thing we *can* do is refresh the launcher badge so that even when
  // the user never opens the app the icon count stays in sync.
  print('Background message received: ${message.notification?.title}');

  // update badge count; the NotificationService is a singleton so it will
  // create the minimal objects it needs in this isolate as well.
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
        // Only Android needs notification channels; Windows/other platforms
        // don't use them. We also restrict badge behavior later to
        // android/windows so extra channels are harmless.
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

        // Initialize local notifications for supported mobile/desktop (Android/Windows only)
        const AndroidInitializationSettings initializationSettingsAndroid =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        const InitializationSettings initializationSettings = InitializationSettings(
          android: initializationSettingsAndroid,
        );
        
        await _localNotifications.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (details) {
            _handleNotificationTap(RemoteMessage(data: {}));
          },
        );

        // set presentation options if running on Android (no-op elsewhere)
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // Request permission using permission_handler for Android 13+
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }
      } else {
        // Request browser permission for Web
        requestWebNotificationPermission();
      }

      // Request permission for iOS/FCM
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized || 
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('User granted notification permission');

        // Get FCM token
        String? token;
        if (kIsWeb) {
          // VAPID key is required for Web deep linking/push
          token = await _messaging.getToken(
            vapidKey: "BPEWU6G83xz5r5NZnJ1-XXcyr54bPj7RqknxvIox9JBaR1Dg9T-WsH5j-5QtzJO_vCYkNSMLuZkH3bgvyxnrIcM",
          );
        } else {
          token = await _messaging.getToken();
        }

        if (token != null) {
          print('FCM Token: $token');
          await saveFCMToken(token);
        }

        // Listen for token refresh
        _messaging.onTokenRefresh.listen(saveFCMToken);

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

            // Handle background messages (app terminated or backgrounded)
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

        // Handle notification tap when app is in background
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

        // Check if app was opened from a notification
        RemoteMessage? initialMessage = await _messaging.getInitialMessage();
        if (initialMessage != null) {
          _handleNotificationTap(initialMessage);
        }
      } else {
        print('Notification permission status: ${settings.authorizationStatus}');
      }
    } catch (e) {
      print('Error initializing notifications: $e');
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
            .update({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
        print('FCM token saved to Firestore');
      }
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  /// Handle foreground messages (when app is open)
  void _handleForegroundMessage(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    // Show native browser notification on Web
    if (notification != null && kIsWeb) {
      showWebNotification(
        notification.title ?? 'Notification',
        notification.body ?? '',
      );
    }

    // Show local notification only on Android/Windows (mobile platforms)
    if (notification != null && !kIsWeb && isAndroidOrWindows) {
      final badgeCount = await getUnreadNotificationCount();

      // local notification on supported platforms
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
            visibility: NotificationVisibility.public, // show on lock screen
            color: Colors.indigo, // optional branding
            number: badgeCount,
          ),
        ),
      );
    }

    // Also show in-app SnackBar for better visibility/interaction
    if (notification != null) {
      String title = notification.title ?? 'Notification';
      String body = notification.body ?? 'You have a new message';
      showInAppNotification(title, body);
    }

    // After handling the message locally we also refresh the app icon badge
    // so that the count increments immediately.  (foreground handler is the
    // only place where the application logic runs while the user is in the
    // app, so it's a good hook.)
    try {
      await updateAppBadge();
    } catch (_) {}

    // Mark notification as received in Firestore if it has our ID
    if (message.data.containsKey('notificationId')) {
      _markNotificationAsReceived(message);
    }
  }

  // Reserved notification ID (kept for future use / iOS badge clear)
  static const int _badgeNotifId = 99998;

  /// Update the app icon badge count to reflect current unread notifications.
  ///
  /// Uses flutter_app_icon_badge to set the launcher icon badge:
  ///   ✔ Samsung One UI, MIUI (Xiaomi), Nova Launcher, iOS — shows badge number
  ///   - Stock Pixel / AOSP — shows a notification dot only (Android limitation)
  ///
  /// Does NOT show a local notification. Real notifications in the shade are
  /// created only when an actual FCM message is received (see
  /// _handleForegroundMessage), not on every app launch.
  Future<void> updateAppBadge() async {
    final count = await getUnreadNotificationCount();

    // only web or android/windows are supported; otherwise do nothing
    if (kIsWeb) {
      setWebBadge(count);
      return;
    }
    if (!isAndroidOrWindows) {
      return;
    }

    try {
      if (count == 0) {
        await clearAppBadge();
        return;
      }
      // OS launcher icon badge (Samsung / MIUI / Nova / iOS)
      try {
        await FlutterAppIconBadge.updateBadge(count);
      } catch (_) {}

      // Android/AOSP dot workaround
      await _localNotifications.show(
        _badgeNotifId,
        '',
        '',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'badge_channel',
            'Notification Count',
            channelDescription: 'Shows your unread notification count.',
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
            visibility: NotificationVisibility.private,
            number: count,
            showWhen: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error updating app badge: $e');
    }
  }

  /// Clear the badge count.
  /// Called when the user opens the Notifications screen.
  Future<void> clearAppBadge() async {
    if (kIsWeb) {
      clearWebBadge();
      return;
    }
    if (!isAndroidOrWindows) return;
    // Clear launcher icon badge
    try {
      await FlutterAppIconBadge.removeBadge();
    } catch (_) {}
    // Cancel any leftover local badge notification (Android)
    try { await _localNotifications.cancel(_badgeNotifId); } catch (_) {}
  }

  // internal flag to avoid spamming the launch notification every time
  // the app comes back to the foreground.  the notification is useful on
  // first launch of a session but not on every resume.
  bool _launchNotifShown = false;

  /// Show a brief local notification when the user opens/resumes the app.
  ///
  /// - only runs once per process (controlled by [_launchNotifShown])
  /// - if there are **no unread notifications** we skip entirely
  ///
  /// Called from the app lifecycle handlers in `main.dart`.
  Future<void> showLaunchNotification() async {
    if (kIsWeb || !isAndroidOrWindows) return;

    // already displayed earlier in this session?
    if (_launchNotifShown) return;

    final unread = await getUnreadNotificationCount();
    if (unread == 0) {
      // nothing to notify about
      _launchNotifShown = true; // still mark so we don't check again
      return;
    }

    try {
      await _localNotifications.show(
        0,
        'A-DACS',
        'Welcome back! You have notifications waiting.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            channelDescription: 'This channel is used for important notifications.',
            styleInformation: const BigTextStyleInformation(
              'The application has been opened. Check your unread messages.',
            ),
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error showing launch notification: $e');
    }

    _launchNotifShown = true;
  }

  /// Handle notification tap (when user taps notification)
  void _handleNotificationTap(RemoteMessage message) {
    print('Notification tapped: ${message.data}');

    // Navigate to NotificationsScreen by default for now
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  /// Mark notification as received
  Future<void> _markNotificationAsReceived(RemoteMessage message) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && message.data.containsKey('notificationId')) {
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(message.data['notificationId'])
            .update({'received': true, 'receivedAt': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      print('Error marking notification as received: $e');
    }
  }

  /// Show a global success message
  static void showSuccess(String message) {
    messengerKey.currentState?.hideCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show a global error message
  static void showError(String message) {
    messengerKey.currentState?.hideCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show a global informational message
  static void showInfo(String message) {
    messengerKey.currentState?.hideCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show in-app notification (for foreground messages)
  /// Uses messengerKey to show notification globally
  static void showInAppNotification(
    String title,
    String body,
  ) {
    messengerKey.currentState?.hideCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.indigo[900],
        margin: const EdgeInsets.all(12),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'OPEN',
          textColor: Colors.amber,
          onPressed: () {
             navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
          },
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                 const Icon(Icons.notifications_active, color: Colors.white, size: 20),
                 const SizedBox(width: 8),
                 Expanded(
                   child: Text(
                     title,
                     style: const TextStyle(
                       fontWeight: FontWeight.bold,
                       fontSize: 16,
                     ),
                   ),
                 ),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Get unread notification count
  Future<int> getUnreadNotificationCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final snapshot = await FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: user.uid)
            .where('read', isEqualTo: false)
            .count()
            .get();
        return snapshot.count ?? 0;
      }
    } catch (e) {
      print('Error getting unread count: $e');
    }
    return 0;
  }

  /// Get stream of unread notification count.
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

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true, 'readAt': FieldValue.serverTimestamp()});
      // refresh launcher badge immediately
      await updateAppBadge();
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  /// Delete FCM token on logout
  Future<void> deleteFCMToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'fcmToken': FieldValue.delete()});
        await _messaging.deleteToken();
      }
    } catch (e) {
      debugPrint('Error deleting FCM token: $e');
    }
  }
}
