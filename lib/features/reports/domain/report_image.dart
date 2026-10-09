/// Pure-Dart rules for report photos, shared by the UI and unit tests.
/// Keep this file free of Flutter imports.
library;

/// Must match `MAX_IMAGE_BYTES` in the backend image validator.
const int maxReportImageBytes = 5 * 1024 * 1024;

/// MIME types the backend accepts (sniffed from magic bytes server-side too).
const Set<String> supportedReportImageMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
};

const Map<String, String> _extensionToMime = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

/// Lower-case extension without the dot, or null when there is none.
String? reportImageExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  return fileName.substring(dot + 1).toLowerCase();
}

/// Resolves the MIME type to send, preferring the file extension (which the
/// picker derives from the real filename) and falling back to a declared type.
String? resolveReportImageContentType(String fileName, [String? declaredMimeType]) {
  final byExtension = _extensionToMime[reportImageExtension(fileName)];
  if (byExtension != null) return byExtension;
  final declared = declaredMimeType?.toLowerCase().trim();
  if (declared != null && supportedReportImageMimeTypes.contains(declared)) {
    return declared;
  }
  return null;
}

/// Returns a user-facing error message, or null when the image is acceptable.
/// Purely advisory — the backend re-validates the real bytes.
String? validateReportImage({
  required String fileName,
  required int sizeBytes,
  String? declaredMimeType,
}) {
  if (sizeBytes <= 0) return 'The selected image is empty.';
  if (sizeBytes > maxReportImageBytes) return 'Image is larger than the 5 MB limit.';
  if (resolveReportImageContentType(fileName, declaredMimeType) == null) {
    return 'Unsupported image. Use a JPEG, PNG or WebP file.';
  }
  return null;
}
