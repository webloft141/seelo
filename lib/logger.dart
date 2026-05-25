import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Safely record an error to Crashlytics (no-op if unavailable).
void logError(Object error, StackTrace stack) {
  try {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
  } catch (_) {}
}

/// Safely record a message to Crashlytics logs.
void logMessage(String message) {
  try {
    FirebaseCrashlytics.instance.log(message);
  } catch (_) {}
}
