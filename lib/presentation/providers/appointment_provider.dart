import 'package:flutter/material.dart';
import '../../domain/entities/appointment.dart';
import '../../domain/usecases/appointment/book_appointment_usecase.dart';
import '../../domain/usecases/appointment/get_patient_appointments_usecase.dart';

class AppointmentProvider with ChangeNotifier {
  final BookAppointmentUseCase bookAppointmentUseCase;
  final GetPatientAppointmentsUseCase getPatientAppointmentsUseCase;

  List<Appointment> _appointments = [];
  bool _isLoading = false;

  AppointmentProvider({
    required this.bookAppointmentUseCase,
    required this.getPatientAppointmentsUseCase,
  });

  List<Appointment> get appointments => _appointments;
  bool get isLoading => _isLoading;

  Future<void> bookAppointment(Appointment appointment) async {
    _isLoading = true;
    notifyListeners();
    try {
      await bookAppointmentUseCase(appointment);
      _appointments.add(appointment);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchPatientAppointments(String patientId) async {
    _isLoading = true;
    notifyListeners();
    try {
      _appointments = await getPatientAppointmentsUseCase(patientId);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
