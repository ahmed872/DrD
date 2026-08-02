import '../entities/doctor.dart';

abstract class DoctorRepository {
  Future<Doctor?> getDoctorById(String doctorId);
  Future<List<Doctor>> getAllDoctors();
  Future<void> updateDoctor(Doctor doctor);
}
