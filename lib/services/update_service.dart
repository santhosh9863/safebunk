import 'dart:math';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum UpdateType { upToDate, optional, required }

class UpdateInfo {
  final String latestVersion;
  final String minimumVersion;
  final bool updateRequired;
  final String updateMessage;
  final String apkDownloadUrl;

  const UpdateInfo({
    required this.latestVersion,
    required this.minimumVersion,
    required this.updateRequired,
    required this.updateMessage,
    required this.apkDownloadUrl,
  });
}

class UpdateService {
  UpdateService._();

  static const _defaultLatestVersion = '1.0.0';
  static const _defaultMinimumVersion = '1.0.0';
  static const _defaultUpdateRequired = false;
  static const _defaultUpdateMessage = '';
  static const _defaultApkDownloadUrl = '';

  static Future<UpdateInfo?> fetchUpdateInfo() async {
    try {
      debugPrint('[UpdateService] Update check started');
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setDefaults(const {
        'latest_version': _defaultLatestVersion,
        'minimum_required_version': _defaultMinimumVersion,
        'update_required': _defaultUpdateRequired,
        'update_message': _defaultUpdateMessage,
        'apk_download_url': _defaultApkDownloadUrl,
      });
      await remoteConfig.setConfigSettings(
  RemoteConfigSettings(
    fetchTimeout: const Duration(seconds: 10),
    minimumFetchInterval: const Duration(hours: 1),
  ),
);
      await remoteConfig.fetchAndActivate();

      final info = UpdateInfo(
        latestVersion: remoteConfig.getString('latest_version'),
        minimumVersion: remoteConfig.getString('minimum_required_version'),
        updateRequired: remoteConfig.getBool('update_required'),
        updateMessage: remoteConfig.getString('update_message'),
        apkDownloadUrl: remoteConfig.getString('apk_download_url'),
      );

      debugPrint('[UpdateService] Remote Config values fetched');
      return info;
    } catch (e) {
      debugPrint('[UpdateService] Remote Config fetch failed: $e');
      return null;
    }
  }

  static Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (e) {
      debugPrint('[UpdateService] PackageInfo failed: $e');
      return '1.0.0';
    }
  }

  static UpdateType determineUpdateType({
    required String currentVersion,
    required UpdateInfo? remoteInfo,
  }) {
    if (remoteInfo == null) return UpdateType.upToDate;

    final current = _parseVersion(currentVersion);
    final latest = _parseVersion(remoteInfo.latestVersion);
    final minimum = _parseVersion(remoteInfo.minimumVersion);

    if (current == null || latest == null || minimum == null) {
      debugPrint('[UpdateService] Version parse failed: current=$currentVersion, latest=${remoteInfo.latestVersion}, minimum=${remoteInfo.minimumVersion}');
      return UpdateType.upToDate;
    }

    if (_isOlder(current, minimum)) {
      debugPrint('[UpdateService] Update required: current=$currentVersion < minimum=${remoteInfo.minimumVersion}');
      return UpdateType.required;
    }

    if (remoteInfo.updateRequired && _isOlder(current, latest)) {
      debugPrint('[UpdateService] Update required: current=$currentVersion < latest=${remoteInfo.latestVersion}');
      return UpdateType.required;
    }

    if (_isOlder(current, latest)) {
      debugPrint('[UpdateService] Update available: $currentVersion < ${remoteInfo.latestVersion}');
      return UpdateType.optional;
    }

    debugPrint('[UpdateService] Already up to date: $currentVersion');
    return UpdateType.upToDate;
  }

  static List<int>? _parseVersion(String version) {
    if (version.isEmpty) return null;
    final parts = version.split('.').map((e) => int.tryParse(e)).toList();
    if (parts.any((p) => p == null)) return null;
    return parts.cast<int>();
  }

  static bool _isOlder(List<int> current, List<int> target) {
    final maxLen = max(current.length, target.length);
    for (var i = 0; i < maxLen; i++) {
      final c = i < current.length ? current[i] : 0;
      final t = i < target.length ? target[i] : 0;
      if (c < t) return true;
      if (c > t) return false;
    }
    return false;
  }
}
