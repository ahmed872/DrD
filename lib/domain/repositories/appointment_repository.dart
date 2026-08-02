import '../entities/appointment.dart';

abstract class AppointmentRepository {
  Future<void> bookAppointment(Appointment appointment);
  Future<List<Appointment>> getPatientAppointments(String patientId);
  Future<List<Appointment>> getDoctorAppointments(
      String doctorId, DateTime date);
  Future<void> updateAppointmentStatus(int appointmentId, String status);
  Future<void> cancelAppointment(int appointmentId);
}
