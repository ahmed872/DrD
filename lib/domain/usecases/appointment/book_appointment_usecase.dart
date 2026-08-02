import '../../entities/appointment.dart';
import '../../repositories/appointment_repository.dart';

class BookAppointmentUseCase {
  final AppointmentRepository repository;

  BookAppointmentUseCase(this.repository);

  Future<void> call(Appointment appointment) {
    return repository.bookAppointment(appointment);
  }
}
