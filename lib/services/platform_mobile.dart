// Mobile/desktop implementation using dart:io to check platform.
import 'dart:io' show Platform;

bool get isAndroidOrWindows => Platform.isAndroid || Platform.isWindows;
