import 'dart:io';

void main() {
  final f = File('lib/presentation/providers/firebase_auth_service.dart');
  var s = f.readAsStringSync();
  s = s.replaceAll('Future<bool> signupWithPhone',
      'Future<void> checkSession() async {\n    try {\n      final user = await _firebaseAuth.authStateChanges().first;\n      if (user != null) {\n        final doc = await _firestore.collection(\'users\').doc(user.uid).get();\n        if (doc.exists) {\n          _userId = user.uid;\n          _userData = doc.data();\n          _emailVerified = true;\n          notifyListeners();\n        }\n      }\n    } catch (e) {\n      print(\'Error checking session: \$e\');\n    }\n  }\n\n  Future<bool> signupWithPhone');
  f.writeAsStringSync(s);
}
