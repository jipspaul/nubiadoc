import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Formulaire d'ajout d'un acte CCAM.
///
/// Émet les valeurs saisies via [onSubmit] quand l'utilisateur valide.
class CcamActForm extends StatefulWidget {
  const CcamActForm({super.key, required this.onSubmit});

  final void Function({
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
  }) onSubmit;

  @override
  State<CcamActForm> createState() => _CcamActFormState();
}

class _CcamActFormState extends State<CcamActForm> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _toothCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  @override
  void dispose() {
    _codeCtrl.dispose();
    _labelCtrl.dispose();
    _toothCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amountText = _amountCtrl.text.trim();
    final amountCents =
        amountText.isEmpty ? null : (double.parse(amountText) * 100).round();
    widget.onSubmit(
      ccamCode: _codeCtrl.text.trim(),
      label: _labelCtrl.text.trim(),
      tooth: _toothCtrl.text.trim().isEmpty ? null : _toothCtrl.text.trim(),
      amountCents: amountCents,
    );
    _codeCtrl.clear();
    _labelCtrl.clear();
    _toothCtrl.clear();
    _amountCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: const Key('field_ccam_code'),
                  controller: _codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Code CCAM',
                    hintText: 'ex. HBQD001',
                  ),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obligatoire' : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  key: const Key('field_ccam_label'),
                  controller: _labelCtrl,
                  decoration: const InputDecoration(labelText: 'Libellé'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obligatoire' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('field_ccam_tooth'),
                  controller: _toothCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dent (optionnel)',
                    hintText: 'ex. 11',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: const Key('field_ccam_amount'),
                  controller: _amountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Montant € (optionnel)',
                    hintText: '0.00',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('btn_add_act'),
            onPressed: _submit,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter l\'acte'),
          ),
        ],
      ),
    );
  }
}
