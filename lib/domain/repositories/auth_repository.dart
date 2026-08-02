abstract class AuthRepository {
  Future<void> signInWithPassword({required String email, required String password});
  Future<void> signUp({required String email, required String password, required String fullName, required String role});
  Future<void> signOut();
  Stream<String?> get authStateChanges;
  String? getCurrentUserId();
}
