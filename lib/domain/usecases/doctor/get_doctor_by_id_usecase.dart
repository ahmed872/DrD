import '../../entities/doctor.dart';
import '../../repositories/doctor_repository.dart';

class GetDoctorByIdUseCase {
  final DoctorRepository repository;

  GetDoctorByIdUseCase(this.repository);

  Future<Doctor?> call(String doctorId) {
    return repository.getDoctorById(doctorId);
  }
}
