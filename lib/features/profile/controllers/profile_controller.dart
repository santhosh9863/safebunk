import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/memory_cache.dart';
import '../../../providers/auth_provider.dart';
import '../models/student_profile.dart';
import '../services/profile_service.dart';
import '../../../core/network/dio_client.dart';

enum ProfileStatus { idle, loading, success, error }

class ProfileState {
  final ProfileStatus status;
  final StudentProfile? profile;
  final String? errorMessage;

  const ProfileState({this.status = ProfileStatus.idle, this.profile, this.errorMessage});

  ProfileState copyWith({ProfileStatus? status, StudentProfile? profile, String? errorMessage}) {
    return ProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

final _profileCacheProvider = Provider<MemoryCache<StudentProfile>>((ref) {
  final cache = MemoryCache<StudentProfile>(ttl: const Duration(minutes: 30));
  ref.watch(cacheManagerProvider).register(cache.clear);
  return cache;
});

final _profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(
    dio: DioClient.instance.dio,
    cache: ref.watch(_profileCacheProvider),
  );
});

class ProfileNotifier extends StateNotifier<ProfileState> {
  final ProfileService _service;

  ProfileNotifier(this._service) : super(const ProfileState());

  Future<void> fetchProfile(String studentId) async {
    state = state.copyWith(status: ProfileStatus.loading, errorMessage: null);
    try {
      final profile = await _service.fetchProfile(studentId);
      state = state.copyWith(status: ProfileStatus.success, profile: profile);
    } catch (e) {
      state = state.copyWith(
        status: ProfileStatus.error,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
}

final profileControllerProvider = StateNotifierProvider.autoDispose<ProfileNotifier, ProfileState>((ref) {
  return ProfileNotifier(ref.watch(_profileServiceProvider));
});
