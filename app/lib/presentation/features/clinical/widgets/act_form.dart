import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Form card for adding a CCAM act to the current session.
///
/// Validates required fields (ccam_code, label) and calls [onSubmit]
/// with the collected values. [loading] disables the submit button while
/// the parent bloc is processing.
class ActForm extends StatefulWidget {
  const ActForm({
    super.key,
    required this.onSubmit,
    this.loading = false,
  });

  final void Function({
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
  }) onSubmit;
  final bool loading;

  @override
  State<ActForm> createState() => _ActFormState();
}

class _ActFormState extends State<ActForm> {
  final _formKey = GlobalKey<FormState>();
  final _ccamController = TextEditingController();
  final _labelController = TextEditingController();
  final _toothController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _ccamController.dispose();
    _labelController.dispose();
    _toothController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final amountText = _amountController.text.trim();
    final amountCents = amountText.isNotEmpty
        ? (double.tryParse(amountText) ?? 0) * 100 ~/ 1
        : null;

    widget.onSubmit(
      ccamCode: _ccamController.text.trim().toUpperCase(),
      label: _labelController.text.trim(),
      tooth: _toothController.text.trim().isNotEmpty
          ? _toothController.text.trim()
          : null,
      amountCents: amountCents,
    );

    _ccamController.clear();
    _labelController.clear();
    _toothController.clear();
    _amountController.clear();
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
              Text('Ajouter un acte CCAM', style: textTheme.titleSmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _ccamController,
                      decoration: const InputDecoration(
                        labelText: 'Code CCAM *',
                        hintText: 'ex. HBMD046',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Requis'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _toothController,
                      decoration: const InputDecoration(
                        labelText: 'Dent',
                        hintText: 'ex. 26',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _labelController,
                decoration: const InputDecoration(labelText: 'Libellé *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Montant (€)',
                  hintText: '0.00',
                  suffixText: '€',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
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
                  label: const Text('Ajouter l\'acte'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
