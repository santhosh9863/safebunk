import 'package:safebunk_shared/safebunk_shared.dart';
import '../core/api/http_client.dart';

class WebProfileRepository extends ProfileRepository {
  WebProfileRepository(this._client);

  final HttpClient _client;
  StudentProfile? _cached;
  DateTime? _cacheTime;
  static const _cacheTtl = Duration(minutes: 10);

  @override
  Future<StudentProfile> getProfile({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheTtl) {
        return _cached!;
      }
    }

    final response = await _client.get('/profile');
    if (!response.success || response.data == null) {
      throw Exception(response.message ?? 'Failed to fetch profile');
    }

    _cached = StudentProfile.fromJson(response.data as Map<String, dynamic>);
    _cacheTime = DateTime.now();
    return _cached!;
  }
}
