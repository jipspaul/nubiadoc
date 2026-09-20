import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Formulaire de création d'une salle de stock (#7182/#7183).
Future<String?> showCreateStockLocationDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const CreateStockLocationDialog(),
  );
}

class CreateStockLocationDialog extends StatefulWidget {
  const CreateStockLocationDialog({super.key});

  @override
  State<CreateStockLocationDialog> createState() =>
      _CreateStockLocationDialogState();
}

class _CreateStockLocationDialogState
    extends State<CreateStockLocationDialog> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle salle'),
      content: SizedBox(
        width: 320,
        child: NubiaTextField(
          key: const Key('new_location_name'),
          controller: _nameController,
          label: 'Nom de la salle',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('confirm_new_location_button'),
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saisissez un nom de salle.')),
              );
              return;
            }
            Navigator.of(context).pop(name);
          },
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
