import 'package:dio/dio.dart';

import '../../../core/cache/memory_cache.dart';
import '../../../core/cache/persistent_cache.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_response_validator.dart';
import '../models/student_profile.dart';

class ProfileService {
  final Dio _dio;
  final MemoryCache<StudentProfile> _cache;

  ProfileService({
    required Dio dio,
    required MemoryCache<StudentProfile> cache,
  })  : _dio = dio,
        _cache = cache;

  Future<StudentProfile> fetchProfile(String studentId) async {
    final cached = _cache.get(studentId);
    if (cached != null) {
      return cached;
    }

    final persisted = PersistentCache.getProfile(
      studentId,
      StudentProfile.fromJson,
    );
    if (persisted != null) {
      _cache.set(studentId, persisted);
      return persisted;
    }

    try {
      final response = await _dio.get(
        ApiConstants.studentBasicDetails,
        queryParameters: {'studentId': studentId},
      );

      ApiResponseValidator.validateContentType(response);

      if (response.data is! Map) {
        throw const ServerException('Invalid profile response');
      }

      final profile = StudentProfile.fromJson(response.data as Map<String, dynamic>);
      _cache.set(studentId, profile);
      await _persistProfile(studentId, profile);
      return profile;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  void clearCache() {
    _cache.clear();
  }

  Future<void> _persistProfile(String studentId, StudentProfile profile) async {
    await PersistentCache.setProfile(studentId, profile.toJson());
  }
}
