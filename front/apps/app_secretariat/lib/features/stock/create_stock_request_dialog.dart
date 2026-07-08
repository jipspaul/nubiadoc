import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pharmacy_picker_sheet.dart';

/// Résultat renvoyé par [CreateStockRequestDialog] à la validation.
typedef CreateStockRequestResult = ({
  String pharmacyId,
  List<StockRequestItem> items,
});

/// Émission d'une demande de stock : choix de la pharmacie destinataire puis
/// saisie d'une ou plusieurs lignes (libellé + quantité + note optionnelle).
Future<CreateStockRequestResult?> showCreateStockRequestDialog(
  BuildContext context,
) {
  return showDialog<CreateStockRequestResult>(
    context: context,
    builder: (_) => const CreateStockRequestDialog(),
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
    return AlertDialog(
      title: const Text('Nouvelle demande de stock'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                key: const Key('stock_request_pharmacy_picker'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.local_pharmacy_outlined),
                title: Text(_pharmacy?.name ?? 'Choisir une pharmacie'),
                subtitle: _pharmacy?.address != null
                    ? Text(_pharmacy!.address!)
                    : null,
                onTap: _pickPharmacy,
              ),
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
                onPressed: () => setState(() => _items.add(_ItemDraft())),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une ligne'),
              ),
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
          key: const Key('confirm_create_stock_request_button'),
          onPressed: _onConfirm,
          child: const Text('Envoyer'),
        ),
      ],
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
            controller: draft.qtyController,
            label: 'Qté',
          ),
        ),
        if (onRemove != null)
          IconButton(
            key: Key('stock_item_remove_$index'),
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
      ],
    );
  }
}
