import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/notification_settings_provider.dart';

/// One-shot-per-launch Gen-Z nudge asking the student to switch PULSE
/// notifications back ON.
///
/// Shown whenever the app is opened fresh (new process) while the master
/// toggle is OFF — "Not now" only dismisses it for that session, so it keeps
/// popping until the student flips the switch.
Future<void> showNotificationNudgeIfOff(
  WidgetRef ref,
  BuildContext context,
) async {
  if (_nudgedThisLaunch) return;
  final prefs = ref.read(notificationSettingsProvider);
  if (prefs.masterEnabled) return;
  _nudgedThisLaunch = true;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.notifications_off_rounded, size: 36),
      title: const Text('You went silent'),
      content: const Text(
        'No class reminders, just you and 75% attendance anxiety. Turn them on?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () async {
            await ref
                .read(notificationSettingsProvider.notifier)
                .setMasterEnabled(true);
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          child: const Text('Turn on'),
        ),
      ],
    ),
  );
}

bool _nudgedThisLaunch = false;
