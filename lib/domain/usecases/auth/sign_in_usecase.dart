import '../../repositories/auth_repository.dart';

class SignInUseCase {
  final AuthRepository repository;

  SignInUseCase(this.repository);

  Future<void> call({required String email, required String password}) {
    return repository.signInWithPassword(email: email, password: password);
  }
}
