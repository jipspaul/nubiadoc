import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../letter_compose_cubit.dart';

/// Libellés français des `kind` acceptés (`VALID_KINDS`, `api/src/letters.rs`).
const _kKindLabels = <String, String>{
  'convocation': 'Convocation',
  'relance': 'Relance',
  'courrier_confrere': 'Courrier confrère',
  'attestation': 'Attestation',
  'autre': 'Autre',
};

/// Résultat renvoyé par [showImportLetterTemplateDialog] à l'import réussi —
/// permet à l'appelant de sélectionner aussitôt le modèle importé (#7156).
typedef ImportLetterTemplateResult = ({
  String name,
  LetterTemplateImportResult imported,
});

/// Import d'un modèle de courrier `.docx` (#7157/#7156) : nom, type, choix du
/// fichier, puis liste des placeholders détectés à la validation.
Future<ImportLetterTemplateResult?> showImportLetterTemplateDialog(
  BuildContext context,
) {
  return showDialog<ImportLetterTemplateResult>(
    context: context,
    builder: (dialogContext) => BlocProvider.value(
      value: context.read<LetterComposeCubit>(),
      child: const ImportLetterTemplateDialog(),
    ),
  );
}

class ImportLetterTemplateDialog extends StatefulWidget {
  const ImportLetterTemplateDialog({super.key});

  @override
  State<ImportLetterTemplateDialog> createState() =>
      _ImportLetterTemplateDialogState();
}

class _ImportLetterTemplateDialogState
    extends State<ImportLetterTemplateDialog> {
  final _nameController = TextEditingController();
  String _kind = 'autre';
  PickedFile? _file;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await GetIt.instance<FilePickerService>().pickFile(
      allowedExtensions: const ['docx'],
    );
    if (picked == null) return;
    setState(() {
      _file = picked;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final file = _file;
    if (name.isEmpty || file == null) {
      setState(
          () => _error = 'Renseignez un nom et choisissez un fichier .docx.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await context.read<LetterComposeCubit>().importTemplate(
          name: name,
          kind: _kind,
          bytes: file.bytes,
          filename: file.name,
        );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _submitting = false;
        _error = failure.message;
      }),
      (imported) => Navigator.of(context).pop((name: name, imported: imported)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('import_letter_template_dialog'),
      title: const Text('Importer un modèle Word'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NubiaTextField(
              key: const Key('import_letter_template_name'),
              controller: _nameController,
              label: 'Nom du modèle',
              enabled: !_submitting,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('import_letter_template_kind'),
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final entry in _kKindLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _kind = value ?? _kind),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('import_letter_template_pick_file'),
              onPressed: _submitting ? null : _pickFile,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(_file?.name ?? 'Choisir un fichier .docx'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('import_letter_template_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        NubiaButton(
          key: const Key('import_letter_template_confirm'),
          label: 'Importer',
          isLoading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
