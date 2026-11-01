import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Mobile/desktop (non-web) : dialogue natif d'enregistrement.
Future<String?> saveFileImpl({
  required Uint8List bytes,
  required String fileName,
}) =>
    FilePicker.platform.saveFile(fileName: fileName, bytes: bytes);
