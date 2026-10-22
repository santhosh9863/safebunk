import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/app_exceptions.dart';
import '../../application/reports_providers.dart';
import '../../data/models/ml_suggestion.dart';
import '../../domain/report_enums.dart';
import '../../domain/report_image.dart';
import '../widgets/duplicate_suggestions_card.dart';

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

  // Optional ML category suggestion. It is never applied automatically.
  CategorySuggestion? _categorySuggestion;
  String? _categorySuggestionError;
  bool _suggestingCategory = false;

  // Photo state.
  Uint8List? _imageBytes;
  String? _imageName;
  String? _imageContentType;
  String? _imageError;
  bool _uploading = false;
  double _uploadProgress = 0;
  String? _uploadedAttachmentId;

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(_clearStaleCategorySuggestion);
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_clearStaleCategorySuggestion);
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  /// A suggestion belongs to the text it was requested for. Editing the
  /// description clears it rather than silently applying a stale prediction.
  void _clearStaleCategorySuggestion() {
    if (_categorySuggestion == null && _categorySuggestionError == null) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _categorySuggestion = null;
      _categorySuggestionError = null;
    });
  }

  Future<void> _suggestCategory() async {
    final description = _descriptionController.text.trim();
    if (description.length < 10) {
      _snack('Add a little more description before requesting a suggestion.');
      return;
    }

    setState(() {
      _suggestingCategory = true;
      _categorySuggestionError = null;
    });

    try {
      final suggestion = await ref
          .read(reportsRepositoryProvider)
          .suggestCategory(description);
      if (!mounted) return;
      setState(() {
        _categorySuggestion = suggestion;
        _suggestingCategory = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _categorySuggestion = null;
        _categorySuggestionError = error.message;
        _suggestingCategory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _categorySuggestion = null;
        _categorySuggestionError =
            'Could not get a category suggestion. Please try again.';
        _suggestingCategory = false;
      });
    }
  }

  void _applyCategorySuggestion(CategorySuggestion suggestion) {
    final category = suggestion.category;
    if (category == null || !_categories.contains(category)) return;
    setState(() => _category = category);
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
      final attachment = await ref
          .read(reportsRepositoryProvider)
          .uploadImage(
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
      _snack(
        'The photo did not upload. Retry it, or remove it to submit without a photo.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final report = await ref
          .read(reportsRepositoryProvider)
          .createReport(
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
        e is ApiException
            ? e.message
            : 'Could not submit the report. Please try again.',
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
                  if (value.length < 3) {
                    return 'Title must be at least 3 characters';
                  }
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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _suggestingCategory ? null : _suggestCategory,
                  icon: _suggestingCategory
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text(
                    _suggestingCategory
                        ? 'Suggesting…'
                        : _categorySuggestion == null
                        ? 'Suggest category'
                        : 'Suggest again',
                  ),
                ),
              ),
              if (_categorySuggestionError != null) ...[
                const SizedBox(height: 8),
                _CategorySuggestionNotice(
                  message: _categorySuggestionError!,
                  isError: true,
                ),
              ],
              if (_categorySuggestion != null) ...[
                const SizedBox(height: 8),
                _CategorySuggestionPanel(
                  suggestion: _categorySuggestion!,
                  selectedCategory: _category,
                  onApply: () => _applyCategorySuggestion(_categorySuggestion!),
                ),
              ],
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
              const SizedBox(height: 20),
              DuplicateSuggestionsCard(
                description:
                    'Optional check against your earlier reports before '
                    'submitting. It never blocks submission, merges, or changes '
                    'a report.',
                checkLabel: 'Check possible duplicates',
                load: () {
                  final description = _descriptionController.text.trim();
                  if (description.length < 10) {
                    throw const InvalidDataException(
                      'Add a little more description before checking for '
                      'duplicates.',
                    );
                  }
                  return ref
                      .read(reportsRepositoryProvider)
                      .suggestDraftDuplicates(
                        description: description,
                        category: _category,
                        location: _locationController.text.trim(),
                      );
                },
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
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your report will be submitted as “Submitted”. '
                        'Campus staff will update its status as it is handled.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                        ),
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

class _CategorySuggestionPanel extends StatelessWidget {
  final CategorySuggestion suggestion;
  final String? selectedCategory;
  final VoidCallback onApply;

  const _CategorySuggestionPanel({
    required this.suggestion,
    required this.selectedCategory,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!suggestion.available) {
      return _CategorySuggestionNotice(
        message:
            '${categorySuggestionFailureMessage(suggestion.reason)} '
            'You can still submit without a suggestion.',
      );
    }

    final category = suggestion.category;
    final supported = category != null && _categories.contains(category);
    final applied = supported && selectedCategory == category;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 17, color: cs.primary),
              const SizedBox(width: 7),
              Text(
                'Suggested category',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            category ?? 'No category',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 5,
            children: [
              if (suggestion.confidence != null)
                _SuggestionMeta(
                  label:
                      'Score ${formatMlScore(suggestion.confidence!)} · not a '
                      'calibrated probability',
                ),
              if (suggestion.modelVersion != null)
                _SuggestionMeta(label: 'Model ${suggestion.modelVersion}'),
            ],
          ),
          if (suggestion.needsManualReview) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.rate_review_outlined,
                  size: 17,
                  color: Color(0xFF8A5300),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    suggestion.decision == CategorySuggestionDecision.abstain
                        ? 'Low confidence — please review the category manually.'
                        : 'The model recommends a manual review of this '
                              'suggestion.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Color(0xFF6B4100),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!supported) ...[
            const SizedBox(height: 8),
            Text(
              'This suggestion is not available in the app’s category list. '
              'Choose a category manually.',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
          if (supported) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: applied ? null : onApply,
                icon: Icon(
                  applied ? Icons.check : Icons.check_circle_outline,
                  size: 17,
                ),
                label: Text(
                  applied
                      ? 'Suggested category selected'
                      : 'Use suggested category',
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Choosing this only changes the category field. You remain in '
              'control and can pick another category.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategorySuggestionNotice extends StatelessWidget {
  final String message;
  final bool isError;

  const _CategorySuggestionNotice({
    required this.message,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isError ? cs.onErrorContainer : cs.onSurfaceVariant;
    final background = isError
        ? cs.errorContainer
        : cs.surfaceContainerHighest.withValues(alpha: 0.6);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11.5, height: 1.35, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionMeta extends StatelessWidget {
  final String label;

  const _SuggestionMeta({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                          ),
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
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onErrorContainer,
                    ),
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
