import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_landing.dart';
import '../features/dashboard/providers/dashboard_providers.dart';
import '../features/dashboard/screens/dashboard_tab_v2.dart';
import '../features/reports/presentation/screens/reports_tab.dart';
import '../features/analytics/screens/analytics_tab.dart';
import '../features/notifications/presentation/notification_nudge.dart';
import '../features/notifications/presentation/notification_observer.dart';
import '../features/settings/screens/settings_tab.dart';
import '../features/staff/presentation/staff_shell_screen.dart';
import '../providers/auth_provider.dart';
import '../services/analytics_service.dart';
import 'web_login_screen.dart';

class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  int _currentIndex = 0;
  bool _redirecting = false;

  void _redirect(Widget destination) {
    if (_redirecting) return;
    _redirecting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => destination),
        (route) => false,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => AnalyticsService.logDashboardOpen());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showNotificationNudgeIfOff(ref, context);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (previous?.status == AuthStatus.authenticated &&
          next.status == AuthStatus.unauthenticated) {
        _redirect(const WebLoginScreen());
      } else if (next.status == AuthStatus.authenticated && next.isStaff) {
        _redirect(const StaffShellScreen());
      }
    });

    final auth = ref.watch(authProvider);
    final landing = authLandingFor(auth);

    if (auth.status == AuthStatus.unknown) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (landing == AuthLanding.staff || landing == AuthLanding.admin) {
      _redirect(const StaffShellScreen());
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (landing == null) {
      _redirect(const WebLoginScreen());
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          const NotificationObserver(),
          IndexedStack(
            index: _currentIndex,
            children: const [
              DashboardTabV2(),
              ReportsTab(),
              AnalyticsTab(),
              SettingsTab(),
            ],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          if (index == 0) {
            ref.read(dashboardTabTriggerProvider.notifier).state++;
            AnalyticsService.logDashboardOpen();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.report_gmailerrorred_outlined),
            selectedIcon: Icon(Icons.report_gmailerrorred),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
