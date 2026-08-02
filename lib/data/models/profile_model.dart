import '../../domain/entities/profile.dart';

class ProfileModel extends Profile {
  const ProfileModel({
    required String id,
    required String fullName,
    required String role,
    String? phone,
  }) : super(id: id, fullName: fullName, role: role, phone: phone);

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] ?? '',
      fullName: json['full_name'] ?? 'Unknown',
      role: json['role'] ?? 'patient',
      phone: json['phone'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'role': role,
      'phone': phone,
    };
  }
}
