// Web-only file: compiled only when targeting Flutter Web.
// Uses dart:js_interop (modern, non-deprecated API) instead of dart:js.
// The stub file (web_notification_helper_stub.dart) provides no-op versions
// for mobile — this file is NOT imported on mobile at all.

import 'dart:js_interop';

// ── JS interop bindings ───────────────────────────────────────────────────────

@JS('Notification.permission')
external String get _notificationPermission;

@JS('Notification.requestPermission')
external JSPromise<JSString> _requestPermission();

@JS('Notification')
@staticInterop
class _JSNotification {
  external factory _JSNotification(String title, JSObject options);
}

// ── Public API (matches stub) ─────────────────────────────────────────────────

/// Ask the browser for notification permission (call once on web init).
void requestWebNotificationPermission() {
  try {
    _requestPermission();
  } catch (e) {
    // Permission already granted/denied or browser doesn't support it
  }
}

/// Show a browser (OS-level) notification if permission is granted.
void showWebNotification(String title, String body) {
  try {
    if (_notificationPermission != 'granted') return;

    final options = {
      'body': body,
      'icon': 'icons/Icon-192.png', // Flutter web default icon path
      'badge': 'icons/Icon-192.png',
      'tag': 'adacs-notification',   // replaces previous notif of same tag
      'renotify': true,
    }.jsify() as JSObject;

    _JSNotification(title, options);
  } catch (e) {
    // Silently ignore — browser may block or API unavailable
  }
}
