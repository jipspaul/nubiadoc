import 'package:flutter/material.dart';
import 'package:nubia_patient/core/utils/file_picker_service.dart';

/// A button that triggers the platform file picker and reports the selected
/// file to the parent via [onFileSelected].
///
/// Uses [FilePickerService] (injectable) so widget tests can provide a stub
/// without relying on native platform channels.
class DocumentFilePickerButton extends StatelessWidget {
  const DocumentFilePickerButton({
    super.key,
    required this.filename,
    required this.onFileSelected,
    this.pickerService,
  });

  final String? filename;
  final void Function({
    required String path,
    required String name,
    required String mime,
  }) onFileSelected;

  /// Overridable in tests. Falls back to [DefaultFilePickerService].
  final FilePickerService? pickerService;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const Key('file_picker_button'),
          onPressed: () => _pick(context),
          icon: const Icon(Icons.attach_file_outlined),
          label: const Text('Choisir un fichier'),
        ),
        if (filename != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              filename!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final service = pickerService ?? const DefaultFilePickerService();
    final result = await service.pickFile();
    if (result != null) {
      onFileSelected(
        path: result.path,
        name: result.name,
        mime: result.mimeType,
      );
    }
  }
}
