import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

class CcamAct {
  final String code;
  final String label;

  /// Tarif de référence CCAM en centimes (facultatif) — sert à pré-remplir le
  /// montant dans l'éditeur d'acte (#3402).
  final int? tarifCents;

  const CcamAct({required this.code, required this.label, this.tarifCents});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CcamAct &&
          other.code == code &&
          other.label == label &&
          other.tarifCents == tarifCents;

  @override
  int get hashCode => Object.hash(code, label, tarifCents);
}

/// Brouillon d'acte saisi dans l'éditeur (#3402) : dent + montant en centimes.
class CcamActDraft {
  final String? tooth;
  final int amountCents;

  const CcamActDraft({this.tooth, required this.amountCents});
}

abstract class GetActsUseCase {
  Future<List<CcamAct>> search(String prefix);
}

class CcamPicker extends StatefulWidget {
  final GetActsUseCase useCase;

  /// Appelé une fois l'acte pleinement saisi (code + dent + montant) via
  /// l'éditeur (#3402). Le montant est en centimes ; la dent est facultative.
  final void Function({
    required String code,
    required String label,
    String? tooth,
    required int amountCents,
  }) onActSubmitted;

  const CcamPicker({
    super.key,
    required this.useCase,
    required this.onActSubmitted,
  });

  @override
  State<CcamPicker> createState() => _CcamPickerState();
}

class _CcamPickerState extends State<CcamPicker> {
  final _controller = TextEditingController();
  List<CcamAct>? _suggestions;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String value) async {
    if (value.length <= 3) {
      if (_suggestions != null) setState(() => _suggestions = null);
      return;
    }
    final results = await widget.useCase.search(value);
    if (!mounted) return;
    setState(() => _suggestions = results.take(8).toList());
  }

  /// Ouvre l'éditeur d'acte (dent + montant) au choix d'un code CCAM (#3402).
  /// Sans saisie, aucun acte n'est envoyé (annulation).
  Future<void> _select(CcamAct act) async {
    final draft = await showDialog<CcamActDraft>(
      context: context,
      builder: (_) => CcamActEditorDialog(act: act),
    );
    if (!mounted || draft == null) return;
    _controller.clear();
    setState(() => _suggestions = null);
    widget.onActSubmitted(
      code: act.code,
      label: act.label,
      tooth: draft.tooth,
      amountCents: draft.amountCents,
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: NubiaTextField(
            key: const Key('ccam_search_field'),
            variant: NubiaTextFieldVariant.search,
            controller: _controller,
            onChanged: _onChanged,
            hint: 'Rechercher un acte CCAM',
          ),
        ),
        if (suggestions != null)
          suggestions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Aucun acte trouvé',
                    key: const Key('ccam_no_results'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                )
              : ListView.builder(
                  key: const Key('ccam_suggestions'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: suggestions.length,
                  itemBuilder: (context, i) => ListRow(
                    key: Key('ccam_act_${suggestions[i].code}'),
                    leading: const Icon(Icons.add_circle_outline, size: 22),
                    title: suggestions[i].label,
                    subtitle: suggestions[i].code,
                    onTap: () => _select(suggestions[i]),
                  ),
                ),
      ],
    );
  }
}

/// Éditeur d'acte CCAM (#3402) : permet de saisir le **numéro de dent** et le
/// **montant** avant l'ajout. Le montant est pré-rempli avec le tarif CCAM de
/// référence si disponible. Retourne un [CcamActDraft] (ou `null` si annulé).
class CcamActEditorDialog extends StatefulWidget {
  final CcamAct act;

  const CcamActEditorDialog({super.key, required this.act});

  @override
  State<CcamActEditorDialog> createState() => _CcamActEditorDialogState();
}

class _CcamActEditorDialogState extends State<CcamActEditorDialog> {
  late final TextEditingController _toothController;
  late final TextEditingController _amountController;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _toothController = TextEditingController();
    // Pré-remplissage du montant avec le tarif de référence (#3402).
    final tarif = widget.act.tarifCents;
    _amountController = TextEditingController(
      text: tarif != null ? _centsToEuros(tarif) : '',
    );
  }

  @override
  void dispose() {
    _toothController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  static String _centsToEuros(int cents) =>
      (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

  /// Parse un montant en euros saisi (« 28,64 » ou « 28.64 ») vers des centimes.
  /// Retourne `null` si la saisie est invalide.
  static int? _eurosToCents(String raw) {
    final normalized = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final euros = double.tryParse(normalized);
    if (euros == null || euros < 0) return null;
    return (euros * 100).round();
  }

  void _submit() {
    final cents = _eurosToCents(_amountController.text);
    if (cents == null) {
      setState(() => _amountError = 'Montant invalide');
      return;
    }
    final tooth = _toothController.text.trim();
    Navigator.of(context).pop(
      CcamActDraft(
        tooth: tooth.isEmpty ? null : tooth,
        amountCents: cents,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('act_editor'),
      title: Text(widget.act.label, style: textTheme.titleMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.act.code, style: textTheme.bodySmall),
          const SizedBox(height: 16),
          NubiaTextField(
            key: const Key('act_editor_tooth_field'),
            variant: NubiaTextFieldVariant.outlined,
            controller: _toothController,
            label: 'Numéro de dent',
            hint: 'ex. 26',
          ),
          const SizedBox(height: 12),
          NubiaTextField(
            key: const Key('act_editor_amount_field'),
            variant: NubiaTextFieldVariant.amount,
            controller: _amountController,
            label: 'Montant',
            errorText: _amountError,
            onChanged: (_) {
              if (_amountError != null) setState(() => _amountError = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('act_editor_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        NubiaButton(
          key: const Key('act_editor_submit'),
          size: NubiaButtonSize.sm,
          icon: Icons.check,
          label: 'Ajouter',
          onPressed: _submit,
        ),
      ],
    );
  }
}
