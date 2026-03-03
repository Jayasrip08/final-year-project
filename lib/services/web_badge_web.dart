// Web-specific implementation for badge/title updates.
// This file is only compiled when `dart.library.html` is available (i.e. web
// builds).  It interacts with the DOM and the experimental Badge API.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

/// Update the document title and attempt to set the app badge.
void setWebBadge(int count) {
  try {
    html.document.title = count > 0 ? '($count) A-DACS' : 'A-DACS';
  } catch (_) {}
  try {
    js.context.callMethod('navigator.setAppBadge', [count]);
  } catch (_) {}
}

/// Clear any title/badge modifications performed by [setWebBadge].
void clearWebBadge() {
  try {
    html.document.title = 'A-DACS';
  } catch (_) {}
  try {
    js.context.callMethod('navigator.clearAppBadge');
  } catch (_) {}
}
