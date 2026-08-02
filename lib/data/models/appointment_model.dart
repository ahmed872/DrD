import '../../domain/entities/appointment.dart';

class AppointmentModel extends Appointment {
  const AppointmentModel({
    required int id,
    required String doctorId,
    required String patientId,
    required String patientName,
    required String patientPhone,
    required int patientAge,
    required String patientGender,
    String? symptoms,
    required DateTime appointmentDate,
    required String startTime,
    required String endTime,
    required String status,
  }) : super(
          id: id,
          doctorId: doctorId,
          patientId: patientId,
          patientName: patientName,
          patientPhone: patientPhone,
          patientAge: patientAge,
          patientGender: patientGender,
          symptoms: symptoms,
          appointmentDate: appointmentDate,
          startTime: startTime,
          endTime: endTime,
          status: status,
        );

  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    return AppointmentModel(
      id: json['id'],
      doctorId: json['doctor_id'],
      patientId: json['patient_id'],
      patientName: json['patient_name'],
      patientPhone: json['patient_phone'],
      patientAge: json['patient_age'],
      patientGender: json['patient_gender'],
      symptoms: json['symptoms'],
      appointmentDate:
          DateTime.tryParse(json['appointment_date'] ?? '') ?? DateTime.now(),
      startTime: json['start_time'],
      endTime: json['end_time'],
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'doctor_id': doctorId,
      'patient_id': patientId,
      'patient_name': patientName,
      'patient_phone': patientPhone,
      'patient_age': patientAge,
      'patient_gender': patientGender,
      'symptoms': symptoms,
      'appointment_date': appointmentDate.toIso8601String().split('T')[0],
      'start_time': startTime,
      'end_time': endTime,
      'status': status,
    };
  }
}
