class Profile {
  final String id;
  final String fullName;
  final String role;
  final String? phone;

  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    this.phone,
  });
}
