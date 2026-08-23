import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pharmacy_picker_sheet.dart';

/// Résultat renvoyé par [CreateStockRequestDialog] à la validation.
typedef CreateStockRequestResult = ({
  String pharmacyId,
  List<StockRequestItem> items,
});

/// Largeur du volet de création — poste fixe, formulaire multi-lignes en
/// tableau (maquette design-v2, point 7 : un dialogue 420px à défilement
/// interne ne convient pas, un volet latéral pleine hauteur si).
const _panelWidth = 480.0;

/// Émission d'une demande de stock : choix de la pharmacie destinataire puis
/// saisie d'une ou plusieurs lignes (libellé + quantité + note optionnelle),
/// dans un volet latéral (pas un dialogue) — les lignes se saisissent en
/// tableau, au clavier, sans défiler.
Future<CreateStockRequestResult?> showCreateStockRequestDialog(
  BuildContext context,
) {
  return showGeneralDialog<CreateStockRequestResult>(
    context: context,
    barrierLabel: 'Nouvelle demande de stock',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      return const Align(
        alignment: Alignment.centerRight,
        child: Material(
          child: SizedBox(
            width: _panelWidth,
            height: double.infinity,
            child: CreateStockRequestDialog(),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final offset = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return SlideTransition(position: offset, child: child);
    },
  );
}

class CreateStockRequestDialog extends StatefulWidget {
  const CreateStockRequestDialog({super.key});

  @override
  State<CreateStockRequestDialog> createState() =>
      _CreateStockRequestDialogState();
}

class _CreateStockRequestDialogState extends State<CreateStockRequestDialog> {
  Pharmacy? _pharmacy;
  final List<_ItemDraft> _items = [_ItemDraft()];

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPharmacy() async {
    final pharmacy = await showPharmacyPickerSheet(context);
    if (pharmacy != null) setState(() => _pharmacy = pharmacy);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Nouvelle demande de stock',
                        style: textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: tokens.borderSubtle),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        key: const Key('stock_request_pharmacy_picker'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.local_pharmacy_outlined),
                        title:
                            Text(_pharmacy?.name ?? 'Choisir une pharmacie'),
                        subtitle: _pharmacy?.address != null
                            ? Text(_pharmacy!.address!)
                            : null,
                        onTap: _pickPharmacy,
                      ),
                      const SizedBox(height: 16),
                      _ItemTableHeader(textTheme: textTheme),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ItemRow(
                            index: i,
                            draft: _items[i],
                            onRemove: _items.length > 1
                                ? () => setState(() => _items.removeAt(i))
                                : null,
                          ),
                        ),
                      TextButton.icon(
                        key: const Key('stock_request_add_item'),
                        onPressed: () =>
                            setState(() => _items.add(_ItemDraft())),
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter une ligne'),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: tokens.borderSubtle),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Annuler'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      key: const Key('confirm_create_stock_request_button'),
                      onPressed: _onConfirm,
                      child: const Text('Envoyer'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onConfirm() {
    final pharmacy = _pharmacy;
    if (pharmacy == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez une pharmacie.')),
      );
      return;
    }
    final items = <StockRequestItem>[];
    for (final draft in _items) {
      final label = draft.labelController.text.trim();
      if (label.isEmpty) continue;
      final qty = int.tryParse(draft.qtyController.text.trim()) ?? 0;
      if (qty <= 0) continue;
      final note = draft.noteController.text.trim();
      items.add(StockRequestItem(
        label: label,
        quantity: qty,
        note: note.isEmpty ? null : note,
      ));
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoutez au moins un article avec une quantité.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop((pharmacyId: pharmacy.id, items: items));
  }
}

class _ItemDraft {
  final labelController = TextEditingController();
  final qtyController = TextEditingController(text: '1');
  final noteController = TextEditingController();

  void dispose() {
    labelController.dispose();
    qtyController.dispose();
    noteController.dispose();
  }
}

/// En-têtes de colonnes du tableau de lignes — mêmes proportions que
/// [_ItemRow] (flex 3 / flex 1 / espace de l'icône supprimer).
class _ItemTableHeader extends StatelessWidget {
  const _ItemTableHeader({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final style = textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: NubiaColors.n500,
    );
    return Row(
      children: [
        Expanded(flex: 3, child: Text('Article', style: style)),
        const SizedBox(width: 8),
        Expanded(child: Text('Qté', style: style)),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.index,
    required this.draft,
    required this.onRemove,
  });

  final int index;
  final _ItemDraft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: NubiaTextField(
            key: Key('stock_item_label_$index'),
            controller: draft.labelController,
            label: 'Article',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: NubiaTextField(
            key: Key('stock_item_qty_$index'),
            variant: NubiaTextFieldVariant.numberStepper,
            controller: draft.qtyController,
            label: 'Qté',
          ),
        ),
        if (onRemove != null)
          IconButton(
            key: Key('stock_item_remove_$index'),
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          )
        else
          const SizedBox(width: 48),
      ],
    );
  }
}
