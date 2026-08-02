import '../../entities/appointment.dart';
import '../../repositories/appointment_repository.dart';

class GetPatientAppointmentsUseCase {
  final AppointmentRepository repository;

  GetPatientAppointmentsUseCase(this.repository);

  Future<List<Appointment>> call(String patientId) {
    return repository.getPatientAppointments(patientId);
  }
}
