import '../models/profile/student_profile.dart';

abstract class ProfileRepository {
  Future<StudentProfile> getProfile({bool forceRefresh = false});
}
