import '../../entities/doctor.dart';
import '../../repositories/doctor_repository.dart';

class UpdateDoctorUseCase {
  final DoctorRepository repository;

  UpdateDoctorUseCase(this.repository);

  Future<void> call(Doctor doctor) {
    return repository.updateDoctor(doctor);
  }
}
