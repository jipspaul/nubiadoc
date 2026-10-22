import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Saisie des lignes d'un nouveau devis avant sa création (#8388) : l'API
/// rejette `POST /v1/cabinet/quotes` en 422 dès que `items` est vide
/// (`validate_quote_items`, #7745), donc le CTA « Nouveau devis » de la
/// fiche patient (#8040) ne peut plus créer directement un devis vide — il
/// doit d'abord faire saisir au moins une ligne (libellé + montant) au
/// praticien.
Future<List<QuoteLineItem>?> showNewQuoteDialog(BuildContext context) {
  return showDialog<List<QuoteLineItem>>(
    context: context,
    builder: (_) => const NewQuoteDialog(),
  );
}

class NewQuoteDialog extends StatefulWidget {
  const NewQuoteDialog({super.key});

  @override
  State<NewQuoteDialog> createState() => _NewQuoteDialogState();
}

class _NewQuoteDialogState extends State<NewQuoteDialog> {
  final List<_LineDraft> _lines = [_LineDraft()];
  String? _error;

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau devis'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < _lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _LineRow(
                    index: i,
                    draft: _lines[i],
                    onRemove: _lines.length > 1
                        ? () => setState(() => _lines.removeAt(i))
                        : null,
                  ),
                ),
              TextButton.icon(
                key: const Key('new_quote_add_line'),
                onPressed: () => setState(() => _lines.add(_LineDraft())),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une ligne'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('new_quote_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('confirm_new_quote_button'),
          onPressed: _onConfirm,
          child: const Text('Créer'),
        ),
      ],
    );
  }

  void _onConfirm() {
    final items = <QuoteLineItem>[];
    for (final line in _lines) {
      final label = line.labelController.text.trim();
      if (label.isEmpty) continue;
      final amountCents = _parseAmountCents(line.amountController.text);
      if (amountCents == null || amountCents <= 0) continue;
      items.add(QuoteLineItem(
        id: '',
        label: label,
        totalCents: amountCents,
        amoShareCents: 0,
        amcShareCents: 0,
        patientShareCents: amountCents,
      ));
    }
    if (items.isEmpty) {
      setState(() => _error =
          'Ajoutez au moins une ligne avec un libellé et un montant.');
      return;
    }
    Navigator.of(context).pop(items);
  }

  int? _parseAmountCents(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final euros = double.tryParse(normalized);
    if (euros == null) return null;
    return (euros * 100).round();
  }
}

class _LineDraft {
  final labelController = TextEditingController();
  final amountController = TextEditingController();

  void dispose() {
    labelController.dispose();
    amountController.dispose();
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.index,
    required this.draft,
    required this.onRemove,
  });

  final int index;
  final _LineDraft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: NubiaTextField(
            key: Key('new_quote_line_label_$index'),
            controller: draft.labelController,
            label: 'Libellé',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: NubiaTextField(
            key: Key('new_quote_line_amount_$index'),
            controller: draft.amountController,
            label: 'Montant (€)',
          ),
        ),
        if (onRemove != null)
          IconButton(
            key: Key('new_quote_line_remove_$index'),
            icon: const Icon(Icons.close),
            tooltip: 'Retirer cette ligne',
            onPressed: onRemove,
          ),
      ],
    );
  }
}
