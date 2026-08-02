class Appointment {
  final int id;
  final String doctorId;
  final String patientId;
  final String patientName;
  final String patientPhone;
  final int patientAge;
  final String patientGender;
  final String? symptoms;
  final DateTime appointmentDate;
  final String startTime;
  final String endTime;
  final String status;

  const Appointment({
    required this.id,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
    required this.patientPhone,
    required this.patientAge,
    required this.patientGender,
    this.symptoms,
    required this.appointmentDate,
    required this.startTime,
    required this.endTime,
    required this.status,
  });
}
