import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Result of a file pick operation.
class PickedFile {
  /// Chemin local — null sur le web (file_picker n'y expose pas de path).
  final String? path;
  final String name;
  final String mimeType;

  /// Contenu du fichier — toujours présent (withData: true), seule source
  /// fiable sur Flutter web.
  final Uint8List bytes;

  const PickedFile({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.bytes,
  });
}

/// Abstract interface for platform file picking.
///
/// Inject a stub in widget tests; the default implementation
/// ([DefaultFilePickerService]) is used at runtime.
abstract class FilePickerService {
  const FilePickerService();

  /// Returns the selected [PickedFile], or `null` if the user cancelled.
  Future<PickedFile?> pickFile({List<String>? allowedExtensions});
}

/// Default runtime implementation backed by the `file_picker` package.
class DefaultFilePickerService extends FilePickerService {
  const DefaultFilePickerService();

  @override
  Future<PickedFile?> pickFile({List<String>? allowedExtensions}) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    final bytes = f.bytes;
    if (bytes == null) return null;
    return PickedFile(
      path: f.path,
      name: f.name,
      mimeType: _mimeFromExtension(f.extension),
      bytes: bytes,
    );
  }
}

String _mimeFromExtension(String? ext) {
  switch (ext?.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'pdf':
      return 'application/pdf';
    default:
      return 'application/octet-stream';
  }
}
