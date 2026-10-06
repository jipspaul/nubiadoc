import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Valeurs saisies dans [CorrespondentFormDialog], transmises à
/// [CorrespondentFormDialog.onSubmit] — le dialogue ne se ferme plus tout
/// seul (#8064) : c'est l'appelant qui décide, une fois la requête faite,
/// via `Navigator.pop` sur le contexte du dialogue en cas de succès.
typedef CorrespondentFormValues = ({
  String displayName,
  String? specialty,
  String? email,
  String? phone,
  String? address,
  String? rpps,
  String? notes,
});

/// Formulaire création/édition d'un correspondant du cabinet (#7193) —
/// `correspondent` null = création.
///
/// Ne ferme plus le dialogue lui-même à la soumission (#8064) : il délègue
/// la requête à [onSubmit] et reste ouvert, saisie intacte, jusqu'à ce que
/// l'appelant le ferme explicitement (typiquement sur succès, via un
/// `BlocListener` qui pop le contexte du dialogue) — un refus serveur ne
/// doit ni fermer le formulaire ni en détruire les `TextEditingController`.
class CorrespondentFormDialog extends StatefulWidget {
  const CorrespondentFormDialog({
    super.key,
    required this.onSubmit,
    this.correspondent,
  });

  final CabinetCorrespondent? correspondent;
  final void Function(CorrespondentFormValues values) onSubmit;

  @override
  State<CorrespondentFormDialog> createState() =>
      _CorrespondentFormDialogState();
}

class _CorrespondentFormDialogState extends State<CorrespondentFormDialog> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _specialtyController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _rppsController;
  late final TextEditingController _notesController;
  bool _displayNameValid = false;
  bool _emailValid = true;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static bool _isValidEmail(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty || _emailRe.hasMatch(trimmed);
  }

  @override
  void initState() {
    super.initState();
    final correspondent = widget.correspondent;
    _displayNameController =
        TextEditingController(text: correspondent?.displayName ?? '');
    _specialtyController =
        TextEditingController(text: correspondent?.specialty ?? '');
    _emailController = TextEditingController(text: correspondent?.email ?? '');
    _phoneController = TextEditingController(text: correspondent?.phone ?? '');
    _addressController =
        TextEditingController(text: correspondent?.address ?? '');
    _rppsController = TextEditingController(text: correspondent?.rpps ?? '');
    _notesController = TextEditingController(text: correspondent?.notes ?? '');
    _displayNameValid = _displayNameController.text.trim().isNotEmpty;
    _emailValid = _isValidEmail(_emailController.text);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _specialtyController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _rppsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _trimmedOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _onValider() {
    widget.onSubmit((
      displayName: _displayNameController.text.trim(),
      specialty: _trimmedOrNull(_specialtyController),
      email: _trimmedOrNull(_emailController),
      phone: _trimmedOrNull(_phoneController),
      address: _trimmedOrNull(_addressController),
      rpps: _trimmedOrNull(_rppsController),
      notes: _trimmedOrNull(_notesController),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.correspondent != null;
    return AlertDialog(
      title: Text(isEdit ? 'Modifier le correspondant' : 'Ajouter un correspondant'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('correspondent_display_name_field'),
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) =>
                    setState(() => _displayNameValid = v.trim().isNotEmpty),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('correspondent_specialty_field'),
                controller: _specialtyController,
                decoration: const InputDecoration(
                  labelText: 'Spécialité (optionnel)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('correspondent_email_field'),
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'E-mail (optionnel)',
                  border: const OutlineInputBorder(),
                  errorText: _emailValid ? null : 'E-mail invalide.',
                ),
                onChanged: (v) =>
                    setState(() => _emailValid = _isValidEmail(v)),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('correspondent_phone_field'),
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Téléphone (optionnel)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('correspondent_address_field'),
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Adresse (optionnel)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('correspondent_rpps_field'),
                controller: _rppsController,
                decoration: const InputDecoration(
                  labelText: 'RPPS (optionnel)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('correspondent_notes_field'),
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optionnel)',
                  border: OutlineInputBorder(),
                ),
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
          key: const Key('correspondent_submit_button'),
          onPressed: _displayNameValid && _emailValid ? _onValider : null,
          child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}
