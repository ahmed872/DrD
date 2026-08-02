class Doctor {
  final String id;
  final String fullName;
  final String? specialization;
  final int avgSessionDuration;
  final int bufferTime;
  final String startTime;
  final String endTime;
  final bool isAvailable;

  const Doctor({
    required this.id,
    required this.fullName,
    this.specialization,
    required this.avgSessionDuration,
    required this.bufferTime,
    required this.startTime,
    required this.endTime,
    required this.isAvailable,
  });
}
