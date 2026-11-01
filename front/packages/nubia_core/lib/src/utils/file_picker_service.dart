import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'file_picker_service_io.dart'
    if (dart.library.html) 'file_picker_service_web.dart' as impl;

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

  /// Prompts a native save dialog for [bytes] and writes it to the chosen
  /// location. Returns the saved path, or `null` if the user cancelled.
  /// On web there is no such dialog/path — the browser triggers its own
  /// download instead (see `file_picker_service_web.dart`) — and this
  /// throws rather than returning silently if delivery isn't possible.
  Future<String?> saveFile({
    required Uint8List bytes,
    required String fileName,
  });
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
      // `PlatformFile.path` throws on web — bytes is the only reliable source there.
      path: kIsWeb ? null : f.path,
      name: f.name,
      mimeType: _mimeFromExtension(f.extension),
      bytes: bytes,
    );
  }

  @override
  Future<String?> saveFile({
    required Uint8List bytes,
    required String fileName,
  }) =>
      // #8533 : sur web, `FilePicker.platform.saveFile` construit le blob
      // mais ne pose aucune ancre de téléchargement dans cette config —
      // livraison explicite via import conditionnel (voir
      // `file_picker_service_web.dart`). Hors web, comportement inchangé
      // (dialogue natif `file_picker`).
      impl.saveFileImpl(bytes: bytes, fileName: fileName);
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
