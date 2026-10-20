/// The two staff-side roles issued by the PULSE backend.
///
/// The role is always parsed from the backend login response (or from the
/// securely stored session that was created from one). Unknown values are
/// rejected rather than defaulting to a privileged role.
enum StaffRole {
  staff('STAFF', 'Staff'),
  admin('ADMIN', 'Administrator');

  const StaffRole(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static StaffRole? tryParse(Object? value) {
    final normalized = value?.toString().trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final role in StaffRole.values) {
      if (role.apiValue == normalized) return role;
    }
    return null;
  }
}

/// A locally provisioned staff/admin session returned by
/// `POST /api/auth/staff/login`.
///
/// This is intentionally separate from the Linways student `SessionData`.
/// The access token is a PULSE backend Bearer token, never a Linways cookie.
class StaffSession {
  final String accessToken;
  final String staffId;
  final String username;
  final String? displayName;
  final StaffRole role;

  const StaffSession({
    required this.accessToken,
    required this.staffId,
    required this.username,
    required this.role,
    this.displayName,
  });

  String get displayLabel {
    final name = displayName?.trim();
    return (name == null || name.isEmpty) ? username : name;
  }

  /// Parses the `{accessToken, staff: {...}}` payload returned by the backend.
  ///
  /// Throws [FormatException] when the token or role is missing/invalid so the
  /// caller cannot accidentally create a session with a guessed role.
  factory StaffSession.fromLoginJson(Map<String, dynamic> json) {
    final accessToken = json['accessToken']?.toString().trim() ?? '';
    final rawStaff = json['staff'];
    if (accessToken.isEmpty || rawStaff is! Map) {
      throw const FormatException('Invalid staff login response');
    }

    final staff = Map<String, dynamic>.from(rawStaff);
    final role = StaffRole.tryParse(staff['role']);
    final staffId = staff['id']?.toString().trim() ?? '';
    final username = staff['username']?.toString().trim() ?? '';

    if (role == null || staffId.isEmpty || username.isEmpty) {
      throw const FormatException('Invalid staff login response');
    }

    final displayName = staff['displayName']?.toString().trim();

    return StaffSession(
      accessToken: accessToken,
      staffId: staffId,
      username: username,
      displayName: (displayName == null || displayName.isEmpty)
          ? null
          : displayName,
      role: role,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'staffId': staffId,
      'username': username,
      'displayName': displayName,
      'role': role.apiValue,
    };
  }

  factory StaffSession.fromJson(Map<String, dynamic> json) {
    final role = StaffRole.tryParse(json['role']);
    final accessToken = json['accessToken']?.toString().trim() ?? '';
    final staffId = json['staffId']?.toString().trim() ?? '';
    final username = json['username']?.toString().trim() ?? '';
    if (role == null ||
        accessToken.isEmpty ||
        staffId.isEmpty ||
        username.isEmpty) {
      throw const FormatException('Invalid stored staff session');
    }

    final displayName = json['displayName']?.toString().trim();
    return StaffSession(
      accessToken: accessToken,
      staffId: staffId,
      username: username,
      displayName: (displayName == null || displayName.isEmpty)
          ? null
          : displayName,
      role: role,
    );
  }
}
