import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

const _originOptions = {
  'phone': 'Téléphone',
  'app': 'Application',
  'web': 'Web',
  'email': 'E-mail',
  'other': 'Autre',
};

const _priorityOptions = {
  'low': 'Basse',
  'medium': 'Moyenne',
  'high': 'Haute',
  'urgent': 'Urgente',
};

const _statusOptions = {
  'open': 'Ouvert',
  'in_progress': 'En cours',
  'done': 'Traité',
  'closed': 'Fermé',
};

/// Résultat renvoyé par [QualificationEditor] à la validation — `null` sur
/// `origin`/`priority` signifie « non renseigné », `status` reste toujours
/// choisi (pas de valeur « vide » possible côté back). `motif` volontairement
/// absent : cloisonnement clinique, cf.
/// `CabinetMessageRepository.updateQualification`.
typedef QualificationEditorResult = ({
  String? origin,
  String? priority,
  String status,
  String? summary,
});

/// Éditeur de qualification d'une conversation cabinet — origine, priorité,
/// statut, synthèse (#7609 : seule l'assignation était éditable jusqu'ici).
class QualificationEditor extends StatefulWidget {
  const QualificationEditor({super.key, required this.conversation});

  final CabinetConversation conversation;

  /// Ouvre l'éditeur ; retourne la qualification saisie, ou `null` si annulé.
  static Future<QualificationEditorResult?> show(
    BuildContext context, {
    required CabinetConversation conversation,
  }) {
    return showDialog<QualificationEditorResult>(
      context: context,
      builder: (_) => QualificationEditor(conversation: conversation),
    );
  }

  @override
  State<QualificationEditor> createState() => _QualificationEditorState();
}

class _QualificationEditorState extends State<QualificationEditor> {
  late String? _origin = widget.conversation.origin;
  late String? _priority = widget.conversation.priority;
  late String _status = widget.conversation.status;
  late final _summaryController =
      TextEditingController(text: widget.conversation.summary);

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(context).pop((
      origin: _origin,
      priority: _priority,
      status: _status,
      summary: _summaryController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('qualification_editor'),
      title: const Text('Qualifier la conversation'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String?>(
              key: const Key('qualification_origin'),
              initialValue: _origin,
              decoration: const InputDecoration(labelText: 'Origine'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Non renseignée')),
                for (final entry in _originOptions.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (v) => setState(() => _origin = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('qualification_priority'),
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priorité'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Non renseignée')),
                for (final entry in _priorityOptions.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (v) => setState(() => _priority = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('qualification_status'),
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Statut'),
              items: [
                for (final entry in _statusOptions.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 12),
            NubiaTextField(
              key: const Key('qualification_summary'),
              controller: _summaryController,
              label: 'Synthèse',
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('qualification_editor_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('qualification_editor_confirm'),
          onPressed: _confirm,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
