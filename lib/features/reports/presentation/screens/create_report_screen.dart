import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/app_exceptions.dart';
import '../../application/reports_providers.dart';
import '../../domain/report_enums.dart';
import '../../domain/report_image.dart';

/// Campus categories offered to students. Free-form values are also accepted by
/// the backend, but a guided list keeps the first version consistent.
const _categories = <String>[
  'Infrastructure',
  'Electrical',
  'Plumbing',
  'Cleanliness',
  'Safety',
  'Network / IT',
  'Academic',
  'Other',
];

class CreateReportScreen extends ConsumerStatefulWidget {
  const CreateReportScreen({super.key});

  @override
  ConsumerState<CreateReportScreen> createState() => _CreateReportScreenState();
}

class _CreateReportScreenState extends ConsumerState<CreateReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _picker = ImagePicker();

  String? _category;
  ReportPriority _priority = ReportPriority.medium;
  bool _submitting = false;

  // Photo state.
  Uint8List? _imageBytes;
  String? _imageName;
  String? _imageContentType;
  String? _imageError;
  bool _uploading = false;
  double _uploadProgress = 0;
  String? _uploadedAttachmentId;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final name = picked.name.isNotEmpty ? picked.name : 'photo.jpg';
    final contentType = resolveReportImageContentType(name, picked.mimeType);
    final error = validateReportImage(
      fileName: name,
      sizeBytes: bytes.length,
      declaredMimeType: picked.mimeType,
    );

    // A previous upload is only discarded once a new image is in hand.
    await _discardUploaded();
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imageName = name;
      _imageContentType = contentType;
      _imageError = error;
      _uploadProgress = 0;
    });

    if (error == null) {
      await _uploadImage();
    }
  }

  Future<void> _uploadImage() async {
    final bytes = _imageBytes;
    final name = _imageName;
    final contentType = _imageContentType;
    if (bytes == null || name == null || contentType == null) return;

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
      _imageError = null;
    });

    try {
      final attachment = await ref.read(reportsRepositoryProvider).uploadImage(
            bytes: bytes,
            fileName: name,
            contentType: contentType,
            onProgress: (sent, total) {
              if (!mounted || total <= 0) return;
              setState(() => _uploadProgress = sent / total);
            },
          );
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadedAttachmentId = attachment.id;
        _uploadProgress = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadProgress = 0;
        _imageError = e is ApiException
            ? e.message
            : 'Upload failed. Retry, or remove the photo and submit without it.';
      });
    }
  }

  Future<void> _removeImage() async {
    await _discardUploaded();
    if (!mounted) return;
    setState(() {
      _imageBytes = null;
      _imageName = null;
      _imageContentType = null;
      _imageError = null;
      _uploading = false;
      _uploadProgress = 0;
    });
  }

  /// Best-effort cleanup of a photo uploaded but not yet attached to a report,
  /// so replacing/removing it does not leave an orphan in storage.
  Future<void> _discardUploaded() async {
    final id = _uploadedAttachmentId;
    _uploadedAttachmentId = null;
    if (id == null) return;
    try {
      await ref.read(reportsRepositoryProvider).deleteAttachment(id);
    } catch (_) {
      // Non-fatal: the object is unlinked and can be cleaned up later.
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_uploading) {
      _snack('Please wait for the photo to finish uploading.');
      return;
    }
    if (_imageBytes != null && _uploadedAttachmentId == null) {
      _snack('The photo did not upload. Retry it, or remove it to submit without a photo.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final report = await ref.read(reportsRepositoryProvider).createReport(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            category: _category,
            location: _locationController.text.trim(),
            priority: _priority.apiValue,
            attachmentId: _uploadedAttachmentId,
          );
      ref.invalidate(reportsListProvider);
      if (!mounted) return;
      Navigator.of(context).pop(report);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack(
        e is ApiException ? e.message : 'Could not submit the report. Please try again.',
      );
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New Report')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _SectionLabel('Issue details'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Water leakage near Block B stairs',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Please add a short title';
                  if (value.length < 3) return 'Title must be at least 3 characters';
                  return null;
                },
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 8,
                maxLength: 4000,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                  hintText: 'Describe what is wrong and where exactly it is.',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Please describe the issue';
                  if (value.length < 10) {
                    return 'Please give a little more detail (10+ characters)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              _SectionLabel('Where is it?'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _locationController,
                maxLength: 160,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  prefixIcon: Icon(Icons.place_outlined),
                  hintText: 'e.g. Block C · 3rd Floor · Room 304',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              _SectionLabel('Category'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.local_offer_outlined),
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Select a category (optional)'),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (value) => setState(() => _category = value),
              ),
              const SizedBox(height: 20),
              _SectionLabel('Priority'),
              const SizedBox(height: 8),
              _PrioritySelector(
                value: _priority,
                onChanged: (p) => setState(() => _priority = p),
              ),
              const SizedBox(height: 20),
              _SectionLabel('Photo (optional)'),
              const SizedBox(height: 8),
              _PhotoField(
                bytes: _imageBytes,
                uploading: _uploading,
                progress: _uploadProgress,
                error: _imageError,
                onAddOrReplace: _pickImage,
                onRemove: _removeImage,
                onRetry: _uploadImage,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your report will be submitted as “Submitted”. '
                        'Campus staff will update its status as it is handled.',
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_submitting ? 'Submitting…' : 'Submit Report'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoField extends StatelessWidget {
  final Uint8List? bytes;
  final bool uploading;
  final double progress;
  final String? error;
  final VoidCallback onAddOrReplace;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  const _PhotoField({
    required this.bytes,
    required this.uploading,
    required this.progress,
    required this.error,
    required this.onAddOrReplace,
    required this.onRemove,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (bytes == null) {
      return OutlinedButton.icon(
        onPressed: onAddOrReplace,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
        label: const Text('Add a photo'),
      );
    }

    final pct = (progress * 100).clamp(0, 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                bytes!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            if (uploading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 120,
                          child: LinearProgressIndicator(
                            value: progress > 0 ? progress : null,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Uploading $pct%',
                          style: const TextStyle(color: Colors.white, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: cs.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(fontSize: 12.5, color: cs.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            if (error != null && !uploading)
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry upload'),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: uploading ? null : onAddOrReplace,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Replace'),
            ),
            TextButton.icon(
              onPressed: uploading ? null : onRemove,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _PrioritySelector extends StatelessWidget {
  final ReportPriority value;
  final ValueChanged<ReportPriority> onChanged;

  const _PrioritySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in ReportPriority.values)
          ChoiceChip(
            label: Text(p.label),
            selected: value == p,
            onSelected: (_) => onChanged(p),
          ),
      ],
    );
  }
}
