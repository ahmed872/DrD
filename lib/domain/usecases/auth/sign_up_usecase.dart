import '../../repositories/auth_repository.dart';

class SignUpUseCase {
  final AuthRepository repository;

  SignUpUseCase(this.repository);

  Future<void> call(
      {required String email,
      required String password,
      required String fullName,
      required String role}) {
    return repository.signUp(
        email: email, password: password, fullName: fullName, role: role);
  }
}
