import '../../domain/entities/doctor.dart';

class DoctorModel extends Doctor {
  const DoctorModel({
    required String id,
    required String fullName,
    String? specialization,
    required int avgSessionDuration,
    required int bufferTime,
    required String startTime,
    required String endTime,
    required bool isAvailable,
  }) : super(
          id: id,
          fullName: fullName,
          specialization: specialization,
          avgSessionDuration: avgSessionDuration,
          bufferTime: bufferTime,
          startTime: startTime,
          endTime: endTime,
          isAvailable: isAvailable,
        );

  factory DoctorModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return DoctorModel(
      id: json['id'] ?? '',
      fullName: profile != null
          ? (profile['full_name'] ?? 'Unknown Doctor')
          : 'Unknown Doctor',
      specialization: json['specialization'],
      avgSessionDuration: (json['avg_session_duration'] ?? 30).toInt(),
      bufferTime: (json['buffer_time'] ?? 0).toInt(),
      startTime: json['start_time'] ?? '09:00:00',
      endTime: json['end_time'] ?? '17:00:00',
      isAvailable: json['is_available'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'specialization': specialization,
      'avg_session_duration': avgSessionDuration,
      'buffer_time': bufferTime,
      'start_time': startTime,
      'end_time': endTime,
      'is_available': isAvailable,
    };
  }
}
