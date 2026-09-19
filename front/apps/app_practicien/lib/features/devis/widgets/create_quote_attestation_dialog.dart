import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Dépôt du texte d'une attestation d'information à faire signer au patient
/// avant la signature du devis (#7202/#7203). Renvoie le corps saisi, ou
/// `null` si annulé.
Future<String?> showCreateQuoteAttestationDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const CreateQuoteAttestationDialog(),
  );
}

class CreateQuoteAttestationDialog extends StatefulWidget {
  const CreateQuoteAttestationDialog({super.key});

  @override
  State<CreateQuoteAttestationDialog> createState() =>
      _CreateQuoteAttestationDialogState();
}

class _CreateQuoteAttestationDialogState
    extends State<CreateQuoteAttestationDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Générer l'attestation d'information"),
      content: SizedBox(
        width: 400,
        child: NubiaTextField(
          key: const Key('quote_attestation_body_field'),
          controller: _controller,
          label: 'Texte remis au patient avant signature',
          maxLines: 8,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('quote_attestation_confirm'),
          onPressed: _onConfirm,
          child: const Text('Générer'),
        ),
      ],
    );
  }

  void _onConfirm() {
    final body = _controller.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Le texte de l'attestation est requis.")),
      );
      return;
    }
    Navigator.of(context).pop(body);
  }
}
