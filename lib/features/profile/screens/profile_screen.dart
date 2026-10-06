import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/profile_controller.dart';
import '../models/student_profile.dart';
import '../../notifications/presentation/providers/notification_settings_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final String studentId;

  const ProfileScreen({super.key, required this.studentId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileControllerProvider.notifier).fetchProfile(widget.studentId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: switch (state.status) {
        ProfileStatus.idle || ProfileStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        ProfileStatus.error => _ErrorView(
          message: state.errorMessage ?? 'Failed to load profile.',
          onRetry: () => ref
              .read(profileControllerProvider.notifier)
              .fetchProfile(widget.studentId),
        ),
        ProfileStatus.success => _ProfileView(
          profile: state.profile!,
        ),
      },
    );
  }
}

class _ProfileView extends ConsumerWidget {
  final StudentProfile profile;

  const _ProfileView({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gender = ref.watch(
      notificationSettingsProvider.select((s) => s.gender),
    );
    final detected = profile.gender;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field('Name', profile.name),
                  const Divider(),
                  _field('Register Number', profile.registerNumber),
                  const Divider(),
                  _field('Department', profile.department),
                  const Divider(),
                  _field('Semester', profile.academicTerm),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildVibeCard(context, ref, gender, detected),
        ],
      ),
    );
  }

  /// "Vibe" picker — picks how messages talk to you. No gender words here;
  /// each option simply sets the wording flavor used in notifications.
  Widget _buildVibeCard(
    BuildContext context,
    WidgetRef ref,
    String gender,
    String detected,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Message vibe',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'How your reminders talk to you.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _vibeChip(context, '👑', 'King', 'male', gender, ref),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _vibeChip(context, '👑', 'Queen', 'female', gender, ref),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _vibeChip(context, '🤖', 'Auto', '', gender, ref),
                ),
              ],
            ),
            if (gender.isEmpty && detected.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Auto-detected from your college profile. You can switch anytime.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vibeChip(
    BuildContext context,
    String emoji,
    String label,
    String value,
    String current,
    WidgetRef ref,
  ) {
    final selected = current == value;
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      avatar: Text(emoji, style: const TextStyle(fontSize: 16)),
      label: Text(label),
      onSelected: (_) => ref
          .read(notificationSettingsProvider.notifier)
          .setGender(value),
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isNotEmpty ? value : '—',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
