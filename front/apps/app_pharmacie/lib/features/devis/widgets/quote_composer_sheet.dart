import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Composer de devis d'officine (ouvert depuis le détail d'une commande) :
/// lignes label / quantité / prix TTC. Le devis est créé en brouillon.
Future<PharmacyQuote?> showQuoteComposerSheet(
  BuildContext context, {
  required String orderId,
}) {
  return showModalBottomSheet<PharmacyQuote>(
    context: context,
    isScrollControlled: true,
    builder: (_) => QuoteComposerSheet(orderId: orderId),
  );
}

class QuoteComposerSheet extends StatefulWidget {
  const QuoteComposerSheet({super.key, required this.orderId});

  final String orderId;

  @override
  State<QuoteComposerSheet> createState() => _QuoteComposerSheetState();
}

class _ItemDraft {
  final label = TextEditingController();
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();

  void dispose() {
    label.dispose();
    qty.dispose();
    price.dispose();
  }

  PharmacyQuoteItem? toItem() {
    final quantity = int.tryParse(qty.text.trim());
    // Prix saisi en euros (virgule acceptée), stocké en centimes.
    final euros = double.tryParse(price.text.trim().replaceAll(',', '.'));
    if (label.text.trim().isEmpty ||
        quantity == null ||
        quantity <= 0 ||
        euros == null ||
        euros < 0) {
      return null;
    }
    return PharmacyQuoteItem(
      label: label.text.trim(),
      quantity: quantity,
      unitPriceCents: (euros * 100).round(),
    );
  }
}

class _QuoteComposerSheetState extends State<QuoteComposerSheet> {
  final _items = <_ItemDraft>[_ItemDraft()];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final items = _items.map((draft) => draft.toItem()).toList();
    if (items.isEmpty || items.any((item) => item == null)) {
      setState(() => _error =
          'Chaque ligne doit avoir un libellé, une quantité et un prix.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final create = GetIt.instance<CreatePharmacyQuoteUseCase>();
    final result = await create(
      // L'identité patient découle de la commande côté backend.
      patientAccountId: '',
      items: items.cast<PharmacyQuoteItem>(),
      orderId: widget.orderId,
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _submitting = false;
        _error = failure.message;
      }),
      (quote) => Navigator.of(context).pop(quote),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nouveau devis', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final (index, draft) in _items.indexed) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: NubiaTextField(
                        key: Key('quote_item_${index}_label'),
                        controller: draft.label,
                        label: 'Produit',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: NubiaTextField(
                        key: Key('quote_item_${index}_qty'),
                        controller: draft.qty,
                        label: 'Qté',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: NubiaTextField(
                        key: Key('quote_item_${index}_price'),
                        controller: draft.price,
                        label: 'Prix TTC (€)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              TextButton.icon(
                key: const Key('quote_add_item'),
                onPressed: _submitting
                    ? null
                    : () => setState(() => _items.add(_ItemDraft())),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une ligne'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              NubiaButton(
                key: const Key('quote_composer_submit'),
                label: 'Créer le devis (brouillon)',
                isLoading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
