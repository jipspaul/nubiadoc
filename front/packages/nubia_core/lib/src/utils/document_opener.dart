import 'package:url_launcher/url_launcher.dart';

/// Opens a document from a signed URL.
///
/// Uses [url_launcher] to delegate to the platform (browser, PDF viewer,
/// image viewer…) based on the MIME type embedded in the URL or provided
/// explicitly.
///
/// Returns `true` if the platform could handle the URL, `false` otherwise.
Future<bool> openDocumentUrl(String signedUrl) async {
  final uri = Uri.tryParse(signedUrl);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Returns a human-readable label for a MIME type.
String mimeTypeLabel(String mimeType) {
  switch (mimeType) {
    case 'application/pdf':
      return 'PDF';
    case 'image/jpeg':
    case 'image/jpg':
      return 'JPEG';
    case 'image/png':
      return 'PNG';
    case 'image/webp':
      return 'WebP';
    case 'application/dicom':
    case 'image/dicom':
      return 'DICOM';
    default:
      return mimeType.split('/').last.toUpperCase();
  }
}
