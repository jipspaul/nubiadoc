import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Sélecteur de praticien pour l'assignation d'une conversation (#7151/#7150
/// — vue « Secrétariat »). Le roster vient de l'état du bloc
/// (`CabinetMessagingConversationsLoaded.practitioners`, même source que
/// l'agenda secrétariat) — pas de désassignation possible : même limite
/// documentée côté API (`PATCH .../conversations/:id`).
class AssigneePicker extends StatelessWidget {
  const AssigneePicker({super.key, required this.practitioners});

  final List<CabinetPractitioner> practitioners;

  /// Ouvre le sélecteur ; retourne le praticien choisi, ou `null` si annulé.
  static Future<CabinetPractitioner?> show(
    BuildContext context, {
    required List<CabinetPractitioner> practitioners,
  }) {
    return showDialog<CabinetPractitioner>(
      context: context,
      builder: (_) => AssigneePicker(practitioners: practitioners),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('assignee_picker'),
      title: const Text('Assigner la conversation'),
      content: SizedBox(
        width: double.maxFinite,
        child: practitioners.isEmpty
            ? const Text(
                'Aucun praticien disponible.',
                key: Key('assignee_picker_empty'),
              )
            : ListView.builder(
                key: const Key('assignee_picker_list'),
                shrinkWrap: true,
                itemCount: practitioners.length,
                itemBuilder: (context, index) {
                  final practitioner = practitioners[index];
                  return ListTile(
                    key: Key('assignee_option_${practitioner.id}'),
                    title: Text(practitioner.displayName),
                    subtitle: practitioner.specialite != null
                        ? Text(practitioner.specialite!)
                        : null,
                    onTap: () => Navigator.of(context).pop(practitioner),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          key: const Key('assignee_picker_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
      ],
    );
  }
}
