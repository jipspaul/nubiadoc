import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Modale d'invitation d'un secrétariat (stub UI).
///
/// Action admin : collecte nom + email et affiche une confirmation. Aucun
/// appel backend n'est câblé (pas de contrat modifié) — l'invitation réelle
/// sera branchée ultérieurement. Cloisonnement : aucune donnée clinique.
class InviteSecretariatDialog extends StatefulWidget {
  const InviteSecretariatDialog({super.key});

  @override
  State<InviteSecretariatDialog> createState() =>
      _InviteSecretariatDialogState();
}

class _InviteSecretariatDialogState extends State<InviteSecretariatDialog> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _nameValid = false;
  bool _emailValid = false;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _canSubmit => _nameValid && _emailValid;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _onInvite() {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Invitation envoyée (stub)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Inviter un secrétariat'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NubiaTextField(
            key: const Key('invite_secretariat_name_field'),
            controller: _nameController,
            label: 'Nom du secrétariat',
            onChanged: (v) => setState(() => _nameValid = v.trim().isNotEmpty),
          ),
          const SizedBox(height: 16),
          NubiaTextField(
            key: const Key('invite_secretariat_email_field'),
            controller: _emailController,
            label: 'Email',
            onChanged: (v) =>
                setState(() => _emailValid = _emailRe.hasMatch(v)),
          ),
        ],
      ),
      actions: [
        NubiaButton(
          label: 'Annuler',
          variant: NubiaButtonVariant.tertiary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        NubiaButton(
          key: const Key('invite_secretariat_submit_button'),
          label: 'Inviter',
          onPressed: _canSubmit ? _onInvite : null,
        ),
      ],
    );
  }
}
