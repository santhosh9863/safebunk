import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/update_service.dart';

enum UpdateStatus { checking, upToDate, updateAvailable, error }

class UpdateState {
  final UpdateStatus status;
  final UpdateInfo? info;
  final UpdateType type;
  final String? error;

  const UpdateState({
    this.status = UpdateStatus.checking,
    this.info,
    this.type = UpdateType.upToDate,
    this.error,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? info,
    UpdateType? type,
    String? error,
  }) {
    return UpdateState(
      status: status ?? this.status,
      info: info ?? this.info,
      type: type ?? this.type,
      error: error ?? this.error,
    );
  }
}

final updateProvider =
    StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  return UpdateNotifier();
});

class UpdateNotifier extends StateNotifier<UpdateState> {
  UpdateNotifier() : super(const UpdateState());

  Future<void> checkForUpdate() async {
    state = const UpdateState(status: UpdateStatus.checking);

    try {
      final currentVersion = await UpdateService.getCurrentVersion();
      final remoteInfo = await UpdateService.fetchUpdateInfo();
      final type = UpdateService.determineUpdateType(
        currentVersion: currentVersion,
        remoteInfo: remoteInfo,
      );

      if (type == UpdateType.upToDate || remoteInfo == null) {
        debugPrint('[UpdateProvider] App is up to date');
        state = const UpdateState(status: UpdateStatus.upToDate);
      } else {
        final label = type == UpdateType.required ? 'required' : 'optional';
        debugPrint('[UpdateProvider] Update available ($label): ${remoteInfo.latestVersion}');
        state = UpdateState(
          status: UpdateStatus.updateAvailable,
          info: remoteInfo,
          type: type,
        );
      }
    } catch (e) {
      debugPrint('[UpdateProvider] Update check error: $e');
      state = UpdateState(
        status: UpdateStatus.error,
        error: e.toString(),
      );
    }
  }
}
