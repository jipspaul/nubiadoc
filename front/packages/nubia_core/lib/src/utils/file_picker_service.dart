import 'package:file_picker/file_picker.dart';

/// Result of a file pick operation.
class PickedFile {
  final String path;
  final String name;
  final String mimeType;

  const PickedFile({
    required this.path,
    required this.name,
    required this.mimeType,
  });
}

/// Abstract interface for platform file picking.
///
/// Inject a stub in widget tests; the default implementation
/// ([DefaultFilePickerService]) is used at runtime.
abstract class FilePickerService {
  const FilePickerService();

  /// Returns the selected [PickedFile], or `null` if the user cancelled.
  Future<PickedFile?> pickFile();
}

/// Default runtime implementation backed by the `file_picker` package.
class DefaultFilePickerService extends FilePickerService {
  const DefaultFilePickerService();

  @override
  Future<PickedFile?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    return PickedFile(
      path: f.path!,
      name: f.name,
      mimeType: f.extension != null
          ? 'application/${f.extension}'
          : 'application/octet-stream',
    );
  }
}
