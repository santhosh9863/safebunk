import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/reports_providers.dart';

/// Displays a report photo served by the PULSE backend.
///
/// The backend mediates downloads (`GET /api/reports/attachments/:id`) behind
/// the student's Bearer session, so the image is fetched with auth headers and
/// never via a public URL.
class ReportImage extends ConsumerWidget {
  final String path;
  final double? height;
  final BoxFit fit;

  const ReportImage({
    super.key,
    required this.path,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(reportsRepositoryProvider).absoluteUrl(path);
    if (url == null) {
      return _Box(height: height, child: _message(context, 'Photo unavailable'));
    }

    final headers = ref.watch(reportImageHeadersProvider);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: headers.when(
        loading: () => _Box(height: height, child: const _Spinner()),
        error: (_, _) => _Box(height: height, child: _message(context, 'Photo unavailable')),
        data: (h) => Image.network(
          url,
          headers: h,
          height: height,
          width: double.infinity,
          fit: fit,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _Box(height: height, child: const _Spinner());
          },
          errorBuilder: (context, _, _) =>
              _Box(height: height, child: _message(context, 'Could not load photo')),
        ),
      ),
    );
  }

  Widget _message(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
        const SizedBox(height: 6),
        Text(text, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2));
}

class _Box extends StatelessWidget {
  final double? height;
  final Widget child;

  const _Box({required this.child, this.height});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: double.infinity,
      color: cs.surfaceContainerLow,
      alignment: Alignment.center,
      child: child,
    );
  }
}
