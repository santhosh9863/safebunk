import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'credential_login_screen.dart';

class WebLoginScreen extends StatelessWidget {
  const WebLoginScreen({super.key});

  static final Uri _linwaysUrl = Uri.parse('https://sfcv4.linways.com/');

  Future<void> _openLinways(BuildContext context) async {
    try {
      await launchUrl(_linwaysUrl, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Linways')),
        );
      }
    }
  }

  void _openCredentialLogin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CredentialLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PULSE'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            const Icon(Icons.school_outlined, size: 64, color: Colors.blue),
            const SizedBox(height: 12),
            Text(
              'Welcome to PULSE',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            _PrimaryCard(onCredentialsTap: () => _openCredentialLogin(context)),
            const SizedBox(height: 16),
            _SecondaryCard(onBrowserTap: () => _openLinways(context)),
          ],
        ),
      ),
    );
  }
}

class _PrimaryCard extends StatelessWidget {
  final VoidCallback onCredentialsTap;

  const _PrimaryCard({required this.onCredentialsTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Login Securely',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Recommended for the full PULSE experience',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _FeatureRow(icon: Icons.sync, text: 'Attendance sync'),
            const SizedBox(height: 10),
            _FeatureRow(icon: Icons.notifications, text: 'Notifications'),
            const SizedBox(height: 10),
            _FeatureRow(icon: Icons.speed, text: 'Faster loading'),
            const SizedBox(height: 10),
            _FeatureRow(icon: Icons.dashboard, text: 'Full dashboard access'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onCredentialsTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Continue with Credentials'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryCard extends StatelessWidget {
  final VoidCallback onBrowserTap;

  const _SecondaryCard({required this.onBrowserTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.language, color: theme.colorScheme.secondary, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Quick Browser Access',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Useful if you forgot your Linways credentials',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: onBrowserTap,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Open Linways'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.green),
        const SizedBox(width: 10),
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
