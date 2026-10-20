import 'staff_session.dart';

/// Admin-only staff account summary returned by `GET /api/staff/users`.
class StaffAccount {
  final String id;
  final String username;
  final String? displayName;
  final StaffRole role;
  final bool active;
  final DateTime? createdAt;

  const StaffAccount({
    required this.id,
    required this.username,
    required this.role,
    required this.active,
    this.displayName,
    this.createdAt,
  });

  String get displayLabel {
    final name = displayName?.trim();
    return (name == null || name.isEmpty) ? username : name;
  }

  factory StaffAccount.fromJson(Map<String, dynamic> json) {
    final role = StaffRole.tryParse(json['role']);
    final id = json['id']?.toString().trim() ?? '';
    final username = json['username']?.toString().trim() ?? '';
    if (role == null || id.isEmpty || username.isEmpty) {
      throw const FormatException('Invalid staff account response');
    }

    final displayName = json['displayName']?.toString().trim();
    final rawCreatedAt = json['createdAt'];

    return StaffAccount(
      id: id,
      username: username,
      displayName: (displayName == null || displayName.isEmpty)
          ? null
          : displayName,
      role: role,
      active: json['active'] == true,
      createdAt: rawCreatedAt is String
          ? DateTime.tryParse(rawCreatedAt)?.toLocal()
          : null,
    );
  }
}
