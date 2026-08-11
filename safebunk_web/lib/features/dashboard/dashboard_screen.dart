import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safebunk_shared/safebunk_shared.dart';
import '../timetable/timetable_screen.dart';
import '../attendance/attendance_screen.dart';
import '../profile/profile_screen.dart';
import '../analytics/analytics_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;

  final _screens = <Widget>[
    const _DashboardTab(),
    const TimetableScreen(),
    const AttendanceScreen(),
    const AnalyticsScreen(),
    const ProfileScreen(),
  ];

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Logout')),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(authRepositoryProvider).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(['Dashboard', 'Timetable', 'Attendance', 'Analytics', 'Profile'][_currentIndex]),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.calendar_today), label: 'Timetable'),
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.analytics), label: 'Analytics'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayScheduleProvider);
    final profileAsync = ref.watch(profileProvider);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(todayScheduleProvider);
        ref.invalidate(profileProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          profileAsync.when(
            data: (profile) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?')),
                title: Text(profile.name, style: theme.textTheme.titleMedium),
                subtitle: Text('${profile.batch} · ${profile.course}'),
              ),
            ),
            loading: () => const Card(child: ListTile(title: Text('Loading...'))),
            error: (e, _) => const Card(child: ListTile(title: Text('Could not load profile'))),
          ),
          const SizedBox(height: 16),
          Text('Today\'s Classes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          todayAsync.when(
            data: (classes) {
              if (classes.isEmpty) {
                return const Card(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No classes today')),
                ));
              }
              return Column(
                children: classes.map((entry) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(entry.hour, style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer)),
                    ),
                    title: Text(entry.subjectName),
                    subtitle: Text('${entry.fromTime} - ${entry.toTime}'),
                  ),
                )).toList(),
              );
            },
            loading: () => const Card(child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )),
            error: (e, _) => Card(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text('Could not load schedule')),
            )),
          ),
        ],
      ),
    );
  }
}
