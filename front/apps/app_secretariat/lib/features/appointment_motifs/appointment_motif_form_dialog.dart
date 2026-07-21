import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Formulaire création/édition d'un motif de RDV — `motif` null = création.
class AppointmentMotifFormDialog extends StatefulWidget {
  const AppointmentMotifFormDialog({super.key, this.motif});

  final AppointmentMotif? motif;

  @override
  State<AppointmentMotifFormDialog> createState() =>
      _AppointmentMotifFormDialogState();
}

class _AppointmentMotifFormDialogState
    extends State<AppointmentMotifFormDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _durationController;
  bool _labelValid = false;

  @override
  void initState() {
    super.initState();
    final motif = widget.motif;
    _labelController = TextEditingController(text: motif?.label ?? '');
    _durationController = TextEditingController(
      text: motif?.defaultDurationMinutes?.toString() ?? '',
    );
    _labelValid = _labelController.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  void _onValider() {
    final duration = int.tryParse(_durationController.text.trim());
    Navigator.of(context).pop(
      (label: _labelController.text.trim(), defaultDurationMinutes: duration),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.motif != null;
    return AlertDialog(
      title: Text(isEdit ? 'Modifier le motif' : 'Ajouter un motif'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('motif_label_field'),
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: 'Libellé',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _labelValid = v.trim().isNotEmpty),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('motif_duration_field'),
            controller: _durationController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Durée par défaut (minutes, optionnel)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('motif_submit_button'),
          onPressed: _labelValid ? _onValider : null,
          child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}
