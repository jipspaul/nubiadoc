import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Résultat renvoyé par [TransferStockDialog] à la validation.
typedef TransferStockResult = ({
  String fromLocationId,
  String toLocationId,
  int quantity,
});

/// Formulaire de transfert d'un article entre deux salles (#7182/#7183).
/// `fromLocationId` est présélectionné sur l'onglet courant.
Future<TransferStockResult?> showTransferStockDialog(
  BuildContext context, {
  required String itemLabel,
  required List<StockLocation> locations,
  required String fromLocationId,
}) {
  return showDialog<TransferStockResult>(
    context: context,
    builder: (_) => TransferStockDialog(
      itemLabel: itemLabel,
      locations: locations,
      fromLocationId: fromLocationId,
    ),
  );
}

class TransferStockDialog extends StatefulWidget {
  const TransferStockDialog({
    super.key,
    required this.itemLabel,
    required this.locations,
    required this.fromLocationId,
  });

  final String itemLabel;
  final List<StockLocation> locations;
  final String fromLocationId;

  @override
  State<TransferStockDialog> createState() => _TransferStockDialogState();
}

class _TransferStockDialogState extends State<TransferStockDialog> {
  late String _fromLocationId = widget.fromLocationId;
  String? _toLocationId;
  final _quantityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _toLocationId = widget.locations
        .firstWhere(
          (l) => l.id != _fromLocationId,
          orElse: () => widget.locations.first,
        )
        .id;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Transférer — ${widget.itemLabel}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('transfer_from_location'),
              initialValue: _fromLocationId,
              decoration: const InputDecoration(labelText: 'Depuis'),
              items: [
                for (final location in widget.locations)
                  DropdownMenuItem(
                    value: location.id,
                    child: Text(location.name),
                  ),
              ],
              onChanged: (v) => setState(() => _fromLocationId = v ?? _fromLocationId),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('transfer_to_location'),
              initialValue: _toLocationId,
              decoration: const InputDecoration(labelText: 'Vers'),
              items: [
                for (final location in widget.locations)
                  DropdownMenuItem(
                    value: location.id,
                    child: Text(location.name),
                  ),
              ],
              onChanged: (v) => setState(() => _toLocationId = v),
            ),
            const SizedBox(height: 12),
            NubiaTextField(
              key: const Key('transfer_quantity'),
              controller: _quantityController,
              label: 'Quantité',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('confirm_transfer_button'),
          onPressed: _onConfirm,
          child: const Text('Transférer'),
        ),
      ],
    );
  }

  void _onConfirm() {
    final quantity = int.tryParse(_quantityController.text.trim());
    final toLocationId = _toLocationId;
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisissez une quantité valide.')),
      );
      return;
    }
    if (toLocationId == null || toLocationId == _fromLocationId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choisissez deux salles différentes.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop((
      fromLocationId: _fromLocationId,
      toLocationId: toLocationId,
      quantity: quantity,
    ));
  }
}
