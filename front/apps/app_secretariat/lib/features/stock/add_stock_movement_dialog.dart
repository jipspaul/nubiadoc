import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Résultat renvoyé par [AddStockMovementDialog] à la validation : `delta`
/// signé (positif pour une réception, positif ou négatif pour un ajustement)
/// et le `reason` associé (`reception`/`adjustment`).
typedef AddStockMovementResult = ({int delta, String reason});

const _kReasonLabels = <String, String>{
  'reception': 'Réception',
  'adjustment': 'Ajustement',
};

/// Formulaire de réception/ajustement de stock (#4146) pour un [StockItem]
/// donné (`label` affiché en titre).
Future<AddStockMovementResult?> showAddStockMovementDialog(
  BuildContext context, {
  required String itemLabel,
}) {
  return showDialog<AddStockMovementResult>(
    context: context,
    builder: (_) => AddStockMovementDialog(itemLabel: itemLabel),
  );
}

class AddStockMovementDialog extends StatefulWidget {
  const AddStockMovementDialog({super.key, required this.itemLabel});

  final String itemLabel;

  @override
  State<AddStockMovementDialog> createState() => _AddStockMovementDialogState();
}

class _AddStockMovementDialogState extends State<AddStockMovementDialog> {
  String _reason = 'reception';
  final _quantityController = TextEditingController();

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Mouvement de stock — ${widget.itemLabel}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('stock_movement_reason'),
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final entry in _kReasonLabels.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: (v) => setState(() => _reason = v ?? _reason),
            ),
            const SizedBox(height: 12),
            NubiaTextField(
              key: const Key('stock_movement_quantity'),
              controller: _quantityController,
              label: _reason == 'reception'
                  ? 'Quantité reçue'
                  : 'Ajustement (ex. -3 ou 5)',
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
          key: const Key('confirm_stock_movement_button'),
          onPressed: _onConfirm,
          child: const Text('Valider'),
        ),
      ],
    );
  }

  void _onConfirm() {
    final raw = int.tryParse(_quantityController.text.trim());
    if (raw == null || raw == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisissez une quantité valide.')),
      );
      return;
    }
    // Une réception est toujours positive quel que soit le signe saisi ;
    // un ajustement conserve le signe saisi par l'utilisateur.
    final delta = _reason == 'reception' ? raw.abs() : raw;
    Navigator.of(context).pop((delta: delta, reason: _reason));
  }
}
