import '../../../../services/api/pulse_backend_service.dart';
import '../models/report_attachment.dart';
import '../models/report_model.dart';

/// Thin data-layer facade over the PULSE backend for Reports.
///
/// All authorization is server-side: the repository never passes a studentId.
class ReportsRepository {
  final PulseBackendService _backend;

  const ReportsRepository(this._backend);

  bool get isEnabled => _backend.isEnabled;

  Future<List<ReportModel>> listMyReports() => _backend.fetchMyReports();

  Future<ReportModel> getReport(String id) => _backend.fetchReport(id);

  Future<ReportModel> createReport({
    required String title,
    required String description,
    String? category,
    String? location,
    String? priority,
    String? attachmentId,
  }) {
    return _backend.createReport(
      title: title,
      description: description,
      category: category,
      location: location,
      priority: priority,
      attachmentId: attachmentId,
    );
  }

  /// Uploads a report photo; [onProgress] drives the upload progress UI.
  Future<ReportAttachment> uploadImage({
    required List<int> bytes,
    required String fileName,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) {
    return _backend.uploadReportImage(
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      onProgress: onProgress,
    );
  }

  Future<void> deleteAttachment(String id) => _backend.deleteAttachment(id);

  String? absoluteUrl(String? path) => _backend.absoluteUrl(path);

  Future<Map<String, String>?> imageAuthHeaders() => _backend.imageAuthHeaders();
}
