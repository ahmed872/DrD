import '../../entities/doctor.dart';
import '../../repositories/doctor_repository.dart';

class GetAllDoctorsUseCase {
  final DoctorRepository repository;

  GetAllDoctorsUseCase(this.repository);

  Future<List<Doctor>> call() {
    return repository.getAllDoctors();
  }
}
