import 'package:flutter/material.dart';
import 'package:nubia_patient/core/utils/file_picker_service.dart';
import 'package:nubia_patient/domain/repositories/account_repository.dart';

/// A button that triggers the image picker (gallery/camera) for the coverage
/// card upload flow and reports the selected file to the parent.
class CoverageCardPickerButton extends StatelessWidget {
  const CoverageCardPickerButton({
    super.key,
    required this.side,
    required this.filename,
    required this.onFileSelected,
    this.pickerService,
  });

  final CoverageCardSide side;
  final String? filename;
  final void Function({
    required String path,
    required String name,
    required String mime,
    required CoverageCardSide side,
  }) onFileSelected;

  /// Overridable in tests without native platform channels.
  final FilePickerService? pickerService;

  @override
  Widget build(BuildContext context) {
    final label = side == CoverageCardSide.recto ? 'Recto' : 'Verso';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: Key('card_picker_${side.name}'),
          onPressed: () => _pick(context),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text('Choisir photo — $label'),
        ),
        if (filename != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
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
        side: side,
      );
    }
  }
}
