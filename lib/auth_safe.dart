import 'package:firebase_auth/firebase_auth.dart';

FirebaseAuth? safeAuth() {
  try {
    return FirebaseAuth.instance;
  } catch (_) {
    return null;
  }
}

User? safeCurrentUser() {
  try {
    return FirebaseAuth.instance.currentUser;
  } catch (_) {
    return null;
  }
}
