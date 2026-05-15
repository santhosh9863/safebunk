import '../models/student_profile.dart';
import '../services/profile_service.dart';

class ProfileRepository {
  final ProfileService _service;

  ProfileRepository({required ProfileService service}) : _service = service;

  Future<StudentProfile> getProfile(String studentId) => _service.fetchProfile(studentId);
}
