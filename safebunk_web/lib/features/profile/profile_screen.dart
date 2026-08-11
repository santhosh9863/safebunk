import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safebunk_shared/safebunk_shared.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(profileProvider);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(profileProvider),
      child: asyncProfile.when(
        data: (profile) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    child: Text(profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 32)),
                  ),
                  const SizedBox(height: 12),
                  Text(profile.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _InfoRow(label: 'Student ID', value: profile.studentId),
            _InfoRow(label: 'Batch', value: profile.batch),
            _InfoRow(label: 'Course', value: profile.course),
            _InfoRow(label: 'Semester', value: profile.semester),
            _InfoRow(label: 'Roll No', value: profile.rollNo),
            if (profile.email.isNotEmpty) _InfoRow(label: 'Email', value: profile.email),
            if (profile.phone.isNotEmpty) _InfoRow(label: 'Phone', value: profile.phone),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(value, style: Theme.of(context).textTheme.bodyMedium),
        subtitle: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
      ),
    );
  }
}
