import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

class InviteMemberDialog extends StatefulWidget {
  const InviteMemberDialog({super.key});

  @override
  State<InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<InviteMemberDialog> {
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  MemberRole _role = MemberRole.secretary;
  bool _emailValid = false;
  bool _firstNameValid = false;
  bool _lastNameValid = false;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _formValid => _emailValid && _firstNameValid && _lastNameValid;

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _onInviter() {
    Navigator.of(context).pop(
      (
        email: _emailController.text.trim(),
        role: _role,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un membre'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('invite_first_name_field'),
            controller: _firstNameController,
            decoration: const InputDecoration(
              labelText: 'Prénom',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) =>
                setState(() => _firstNameValid = v.trim().isNotEmpty),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('invite_last_name_field'),
            controller: _lastNameController,
            decoration: const InputDecoration(
              labelText: 'Nom',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) =>
                setState(() => _lastNameValid = v.trim().isNotEmpty),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('invite_email_field'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) =>
                setState(() => _emailValid = _emailRe.hasMatch(v)),
          ),
          const SizedBox(height: 16),
          DropdownButton<MemberRole>(
            key: const Key('invite_role_dropdown'),
            value: _role,
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                value: MemberRole.admin,
                child: Text('admin'),
              ),
              DropdownMenuItem(
                value: MemberRole.practitioner,
                child: Text('practitioner'),
              ),
              DropdownMenuItem(
                value: MemberRole.secretary,
                child: Text('secretary'),
              ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _role = v);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('invite_submit_button'),
          onPressed: _formValid ? _onInviter : null,
          child: const Text('Inviter'),
        ),
      ],
    );
  }
}
