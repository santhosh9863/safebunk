import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_landing.dart';
import '../../../providers/auth_provider.dart';
import '../../../screens/main_shell_screen.dart';
import '../../../screens/web_login_screen.dart';
import 'staff_account_tab.dart';
import 'staff_accounts_tab.dart';
import 'staff_navigation.dart';
import 'staff_reports_tab.dart';

/// Staff/admin home. The available sections are derived from the backend-issued
/// role, and a role change or logout immediately returns the user to the
/// correct login/home area.
class StaffShellScreen extends ConsumerStatefulWidget {
  const StaffShellScreen({super.key});

  @override
  ConsumerState<StaffShellScreen> createState() => _StaffShellScreenState();
}

class _StaffShellScreenState extends ConsumerState<StaffShellScreen> {
  int _currentIndex = 0;
  bool _redirecting = false;

  void _scheduleRedirect(Widget destination) {
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
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.unknown) return;
      final landing = authLandingFor(next);
      if (landing == AuthLanding.student) {
        _scheduleRedirect(const MainShellScreen());
      } else if (landing == null) {
        _scheduleRedirect(const WebLoginScreen());
      }
    });

    final auth = ref.watch(authProvider);
    final landing = authLandingFor(auth);

    if (auth.status == AuthStatus.unknown) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (landing == AuthLanding.student) {
      _scheduleRedirect(const MainShellScreen());
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final session = auth.staffSession;
    if (landing == null || session == null) {
      _scheduleRedirect(const WebLoginScreen());
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final sections = staffSectionsFor(session.role);
    final index = _currentIndex.clamp(0, sections.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [for (final section in sections) _sectionWidget(section)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          setState(() => _currentIndex = value);
        },
        destinations: [for (final section in sections) _destination(section)],
      ),
    );
  }

  Widget _sectionWidget(StaffSection section) {
    return switch (section) {
      StaffSection.reports => const StaffReportsTab(),
      StaffSection.staffAccounts => const StaffAccountsTab(),
      StaffSection.account => const StaffAccountTab(),
    };
  }

  NavigationDestination _destination(StaffSection section) {
    return switch (section) {
      StaffSection.reports => const NavigationDestination(
        icon: Icon(Icons.report_gmailerrorred_outlined),
        selectedIcon: Icon(Icons.report_gmailerrorred),
        label: 'Reports',
      ),
      StaffSection.staffAccounts => const NavigationDestination(
        icon: Icon(Icons.manage_accounts_outlined),
        selectedIcon: Icon(Icons.manage_accounts),
        label: 'Staff Access',
      ),
      StaffSection.account => const NavigationDestination(
        icon: Icon(Icons.account_circle_outlined),
        selectedIcon: Icon(Icons.account_circle),
        label: 'Account',
      ),
    };
  }
}
