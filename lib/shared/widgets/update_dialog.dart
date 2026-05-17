import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final UpdateType updateType;

  const UpdateDialog({
    super.key,
    required this.info,
    required this.updateType,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isLaunching = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRequired = widget.updateType == UpdateType.required;

    return PopScope(
      canPop: !isRequired && !_isLaunching,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.system_update_rounded,
              color: theme.colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Text('Update Available'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version of PULSE is available.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.info.updateMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                widget.info.updateMessage,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
            _InfoRow(label: 'Available version', value: widget.info.latestVersion),
            const SizedBox(height: 4),
            _InfoRow(
              label: 'Update type',
              value: isRequired ? 'Required' : 'Optional',
            ),
            if (isRequired) ...[
              const SizedBox(height: 12),
              Text(
                'You must update to continue using PULSE.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!isRequired)
            TextButton(
              onPressed: _isLaunching ? null : () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          FilledButton.icon(
            onPressed: _isLaunching ? null : () => _onUpdateNow(context),
            icon: _isLaunching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new, size: 18),
            label: Text(_isLaunching ? 'Opening...' : 'Update Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _onUpdateNow(BuildContext context) async {
    if (_isLaunching) return;
    setState(() => _isLaunching = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final uri = Uri.tryParse(widget.info.apkDownloadUrl);
      if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
        debugPrint('[UpdateDialog] Invalid download URL: ${widget.info.apkDownloadUrl}');
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Invalid download URL. Please try again later.')),
          );
        }
        return;
      }

      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) {
        debugPrint('[UpdateDialog] APK URL launched successfully');
        if (mounted) {
          navigator.pop();
          _showInstallGuidance();
        }
      } else {
        debugPrint('[UpdateDialog] Failed to launch APK URL');
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Could not open download page. Please try again.')),
          );
        }
      }
    } catch (e) {
      debugPrint('[UpdateDialog] URL launch error: $e');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLaunching = false);
    }
  }

  void _showInstallGuidance() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Theme.of(sheetContext).colorScheme.primary, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Install Update',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'If installation is blocked:\nSettings → Allow installs from this source',
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
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
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(value, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
