import 'package:flutter/material.dart';

import '../models/prescription.dart';

/// Formulaire de création d'ordonnance.
///
/// Sélecteur patient + lignes médicament + bouton "Créer l'ordonnance".
/// Appelle [onSubmit] avec le patientId et les items validés.
class PrescriptionForm extends StatefulWidget {
  const PrescriptionForm({
    super.key,
    required this.patients,
    required this.onSubmit,
  });

  final List<PatientSummary> patients;
  final void Function(String patientId, List<PrescriptionItem> items) onSubmit;

  @override
  State<PrescriptionForm> createState() => _PrescriptionFormState();
}

class _PrescriptionFormState extends State<PrescriptionForm> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedPatientId;
  final List<_ItemDraft> _items = [_ItemDraft()];

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _PatientDropdown(
                  patients: widget.patients,
                  value: _selectedPatientId,
                  onChanged: (v) => setState(() => _selectedPatientId = v),
                ),
                const SizedBox(height: 24),
                Text(
                  'Médicaments',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ..._items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final draft = entry.value;
                  return _MedicationItemRow(
                    key: ValueKey(draft),
                    index: i,
                    draft: draft,
                    canRemove: _items.length > 1,
                    onRemove: () => setState(() => _items.removeAt(i)),
                  );
                }),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('btn_add_item'),
                  onPressed: () => setState(() => _items.add(_ItemDraft())),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un médicament'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              key: const Key('btn_create'),
              onPressed: _submit,
              child: const Text("Créer l'ordonnance"),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (_selectedPatientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un patient')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final items = _items
        .map(
          (d) => PrescriptionItem(
            label: d.labelController.text.trim(),
            posology: d.posologyController.text.trim(),
            duration: d.durationController.text.trim(),
            quantity: d.quantityController.text.trim(),
            form: d.formController.text.trim().isEmpty
                ? null
                : d.formController.text.trim(),
          ),
        )
        .toList();
    widget.onSubmit(_selectedPatientId!, items);
  }

  @override
  void dispose() {
    for (final d in _items) {
      d.dispose();
    }
    super.dispose();
  }
}

class _PatientDropdown extends StatelessWidget {
  const _PatientDropdown({
    required this.patients,
    required this.value,
    required this.onChanged,
  });

  final List<PatientSummary> patients;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: const Key('dropdown_patient'),
      value: value,
      decoration: const InputDecoration(
        labelText: 'Patient',
        border: OutlineInputBorder(),
      ),
      items: patients
          .map(
            (p) => DropdownMenuItem(
              value: p.id,
              child: Text(p.name),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: (v) => v == null ? 'Veuillez sélectionner un patient' : null,
    );
  }
}

class _MedicationItemRow extends StatelessWidget {
  const _MedicationItemRow({
    super.key,
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onRemove,
  });

  final int index;
  final _ItemDraft draft;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Médicament ${index + 1}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const Spacer(),
                if (canRemove)
                  IconButton(
                    key: Key('btn_remove_item_$index'),
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                    iconSize: 20,
                    tooltip: 'Supprimer',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: Key('field_label_$index'),
              controller: draft.labelController,
              decoration: const InputDecoration(
                labelText: 'Dénomination *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: Key('field_form_$index'),
              controller: draft.formController,
              decoration: const InputDecoration(
                labelText: 'Forme galénique',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: Key('field_posology_$index'),
              controller: draft.posologyController,
              decoration: const InputDecoration(
                labelText: 'Posologie *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: Key('field_duration_$index'),
                    controller: draft.durationController,
                    decoration: const InputDecoration(
                      labelText: 'Durée *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: Key('field_quantity_$index'),
                    controller: draft.quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Quantité *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Brouillon mutable d'une ligne médicament dans le formulaire.
class _ItemDraft {
  final labelController = TextEditingController();
  final formController = TextEditingController();
  final posologyController = TextEditingController();
  final durationController = TextEditingController();
  final quantityController = TextEditingController();

  void dispose() {
    labelController.dispose();
    formController.dispose();
    posologyController.dispose();
    durationController.dispose();
    quantityController.dispose();
  }
}
