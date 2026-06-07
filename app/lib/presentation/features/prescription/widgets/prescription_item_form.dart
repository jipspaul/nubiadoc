import 'package:flutter/material.dart';
import 'package:nubia_patient/domain/entities/prescription.dart';

/// Form card for adding a medication line to a prescription.
///
/// Validates required fields (label, posology, duration, quantity) and calls
/// [onSubmit] with the collected values. Resets after each submission.
class PrescriptionItemForm extends StatefulWidget {
  const PrescriptionItemForm({
    super.key,
    required this.onSubmit,
    this.loading = false,
  });

  final void Function(PrescriptionItem item) onSubmit;
  final bool loading;

  @override
  State<PrescriptionItemForm> createState() => _PrescriptionItemFormState();
}

class _PrescriptionItemFormState extends State<PrescriptionItemForm> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _formController = TextEditingController();
  final _posologyController = TextEditingController();
  final _durationController = TextEditingController();
  final _quantityController = TextEditingController();

  @override
  void dispose() {
    _labelController.dispose();
    _formController.dispose();
    _posologyController.dispose();
    _durationController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    widget.onSubmit(
      PrescriptionItem(
        label: _labelController.text.trim(),
        form: _formController.text.trim().isNotEmpty
            ? _formController.text.trim()
            : null,
        posology: _posologyController.text.trim(),
        duration: _durationController.text.trim(),
        quantity: _quantityController.text.trim(),
      ),
    );

    _labelController.clear();
    _formController.clear();
    _posologyController.clear();
    _durationController.clear();
    _quantityController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ajouter un médicament', style: textTheme.titleSmall),
              const SizedBox(height: 12),
              TextFormField(
                controller: _labelController,
                decoration: const InputDecoration(labelText: 'Médicament *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _formController,
                      decoration: const InputDecoration(
                        labelText: 'Forme',
                        hintText: 'comprimés, sirop…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _quantityController,
                      decoration:
                          const InputDecoration(labelText: 'Quantité *'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _posologyController,
                decoration: const InputDecoration(
                  labelText: 'Posologie *',
                  hintText: '1 cp matin et soir',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _durationController,
                decoration: const InputDecoration(
                  labelText: 'Durée *',
                  hintText: '7 jours',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.loading ? null : _submit,
                  icon: widget.loading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Ajouter'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
