import '../models/api_response.dart';
import '../models/profile/student_profile.dart';

abstract class ProfileService {
  Future<ApiResponse<StudentProfile>> getProfile();
}
