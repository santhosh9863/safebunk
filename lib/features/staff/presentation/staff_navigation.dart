import '../../../models/auth/staff_session.dart';

/// Sections available to a staff-side identity.
///
/// STAFF accounts never receive the staff-account-management section. The
/// backend also rejects that endpoint for STAFF, so this is an additional UI
/// boundary rather than the only one.
enum StaffSection { reports, staffAccounts, account }

List<StaffSection> staffSectionsFor(StaffRole role) {
  return [
    StaffSection.reports,
    if (role == StaffRole.admin) StaffSection.staffAccounts,
    StaffSection.account,
  ];
}
