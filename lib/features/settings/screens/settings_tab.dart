import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../profile/controllers/profile_controller.dart';
import '../../../providers/auth_provider.dart';
import '../providers/settings_providers.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileState = ref.watch(profileControllerProvider);
    final authState = ref.watch(authProvider);
    final darkMode = ref.watch(darkModeProvider);
    final attendanceAlerts = ref.watch(attendanceAlertsProvider);
    final lowWarning = ref.watch(lowAttendanceWarningProvider);
    final dailyReminder = ref.watch(dailyReminderProvider);
    final weeklySummary = ref.watch(weeklySummaryProvider);

    final profile = profileState.profile;
    final displayName = profile?.name ?? (authState.username ?? 'Student');
    final department = profile?.department ?? '';
    final semester = profile?.currentSem ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const SizedBox(height: 8),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (department.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              department,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (semester.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              'Semester $semester',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (profileState.status == ProfileStatus.loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          _SettingsCard(
            title: 'Appearance',
            children: [
              _SettingsRow(
                label: 'Dark Mode',
                subtitle: 'Switch between light and dark theme.',
                trailing: Switch.adaptive(
                  value: darkMode,
                  activeTrackColor: theme.colorScheme.primary,
                  onChanged: (v) => ref.read(darkModeProvider.notifier).state = v,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _SettingsCard(
            title: 'Notifications',
            children: [
              _SettingsRow(
                label: 'Attendance Alerts',
                subtitle: 'Get notified about daily attendance updates.',
                trailing: Switch.adaptive(
                  value: attendanceAlerts,
                  activeTrackColor: theme.colorScheme.primary,
                  onChanged: (v) {
                    ref.read(attendanceAlertsProvider.notifier).state = v;
                    ref.read(notificationStateStoreProvider).setToggleAttendanceAlerts(v);
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Divider(height: 1),
              ),
              _SettingsRow(
                label: 'Low Attendance Warning',
                subtitle: 'Alert when attendance drops below target.',
                trailing: Switch.adaptive(
                  value: lowWarning,
                  activeTrackColor: theme.colorScheme.primary,
                  onChanged: (v) {
                    ref.read(lowAttendanceWarningProvider.notifier).state = v;
                    ref.read(notificationStateStoreProvider).setToggleLowAttendanceWarning(v);
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Divider(height: 1),
              ),
              _SettingsRow(
                label: 'Daily Reminder',
                subtitle: 'Gentle daily check-in reminder.',
                trailing: Switch.adaptive(
                  value: dailyReminder,
                  activeTrackColor: theme.colorScheme.primary,
                  onChanged: (v) {
                    ref.read(dailyReminderProvider.notifier).state = v;
                    ref.read(notificationStateStoreProvider).setToggleDailyReminder(v);
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Divider(height: 1),
              ),
              _SettingsRow(
                label: 'Weekly Summary',
                subtitle: 'Weekly attendance summary notification.',
                trailing: Switch.adaptive(
                  value: weeklySummary,
                  activeTrackColor: theme.colorScheme.primary,
                  onChanged: (v) {
                    ref.read(weeklySummaryProvider.notifier).state = v;
                    ref.read(notificationStateStoreProvider).setToggleWeeklySummary(v);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _SettingsCard(
            title: 'About',
            children: [
              Center(
                child: SizedBox(
                  width: 240,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Version 1.0.0+1',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PULSE \u2014 Attendance Intelligence',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _PrivacyNote(),
                      const SizedBox(height: 16),
                      const _SignatureSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _SettingsCard(
            title: 'Account',
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmAndLogout(context, ref),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Logout'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _confirmAndLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Credentials are used only for secure attendance syncing with your college portal.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _SignatureSection extends StatefulWidget {
  const _SignatureSection();

  @override
  State<_SignatureSection> createState() => _SignatureSectionState();
}

class _SignatureSectionState extends State<_SignatureSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = _controller.drive(CurveTween(curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Created by',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Santhosh Krishna R',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: cs.onSurfaceVariant.withValues(alpha: 0.75),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'From final year BCA C Sec.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        FadeTransition(
          opacity: _fade,
          child: Text(
            'Built during attendance anxiety.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant.withValues(alpha: 0.78),
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final Widget trailing;

  const _SettingsRow({
    required this.label,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}


