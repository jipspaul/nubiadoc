import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Résultat renvoyé par [showAddQuoteAttachmentDialog] à la validation.
/// Exactement un de `documentId`/`templateRef` est renseigné, jamais les
/// deux — même contrainte que `POST /v1/cabinet/quotes/:id/attachments`
/// (`quote_attachment_source_xor`).
typedef AddQuoteAttachmentResult = ({
  QuoteAttachmentKind kind,
  String? documentId,
  String? templateRef,
});

/// Choix d'une pièce à joindre à l'envoi d'un devis (#7202/#7203) : un
/// consentement ou une ordonnance déjà numérisés dans le dossier patient,
/// ou un modèle de courrier.
Future<AddQuoteAttachmentResult?> showAddQuoteAttachmentDialog(
  BuildContext context, {
  required List<PatientDocument> consents,
  required List<PatientDocument> prescriptions,
  required List<LetterTemplate> letterTemplates,
}) {
  return showDialog<AddQuoteAttachmentResult>(
    context: context,
    builder: (_) => AddQuoteAttachmentDialog(
      consents: consents,
      prescriptions: prescriptions,
      letterTemplates: letterTemplates,
    ),
  );
}

class AddQuoteAttachmentDialog extends StatefulWidget {
  const AddQuoteAttachmentDialog({
    super.key,
    required this.consents,
    required this.prescriptions,
    required this.letterTemplates,
  });

  final List<PatientDocument> consents;
  final List<PatientDocument> prescriptions;
  final List<LetterTemplate> letterTemplates;

  @override
  State<AddQuoteAttachmentDialog> createState() =>
      _AddQuoteAttachmentDialogState();
}

class _AddQuoteAttachmentDialogState extends State<AddQuoteAttachmentDialog> {
  QuoteAttachmentKind? _kind;
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter une pièce jointe'),
      content: SizedBox(
        width: 360,
        child: _kind == null ? _buildKindPicker() : _buildItemPicker(_kind!),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        if (_kind != null)
          ElevatedButton(
            key: const Key('add_quote_attachment_confirm'),
            onPressed: _selectedId == null ? null : _onConfirm,
            child: const Text('Ajouter'),
          ),
      ],
    );
  }

  Widget _buildKindPicker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const Key('add_quote_attachment_kind_consent'),
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('Consentement'),
          onTap: () => setState(() => _kind = QuoteAttachmentKind.consent),
        ),
        ListTile(
          key: const Key('add_quote_attachment_kind_prescription'),
          leading: const Icon(Icons.medication_outlined),
          title: const Text('Ordonnance'),
          onTap: () => setState(() => _kind = QuoteAttachmentKind.prescription),
        ),
        ListTile(
          key: const Key('add_quote_attachment_kind_letter'),
          leading: const Icon(Icons.mail_outlined),
          title: const Text('Courrier'),
          onTap: () => setState(() => _kind = QuoteAttachmentKind.letter),
        ),
      ],
    );
  }

  Widget _buildItemPicker(QuoteAttachmentKind kind) {
    final items = switch (kind) {
      QuoteAttachmentKind.consent =>
        widget.consents.map((d) => (id: d.id, label: d.filename)).toList(),
      QuoteAttachmentKind.prescription =>
        widget.prescriptions.map((d) => (id: d.id, label: d.filename)).toList(),
      QuoteAttachmentKind.letter =>
        widget.letterTemplates.map((t) => (id: t.id, label: t.name)).toList(),
      QuoteAttachmentKind.other => const <({String id, String label})>[],
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () => setState(() {
            _kind = null;
            _selectedId = null;
          }),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Changer de type'),
        ),
        if (items.isEmpty)
          const Padding(
            key: Key('add_quote_attachment_items_empty'),
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Aucun document disponible dans le dossier patient.'),
          )
        else
          Flexible(
            child: ListView(
              key: const Key('add_quote_attachment_items_list'),
              shrinkWrap: true,
              children: [
                for (final item in items)
                  RadioListTile<String>(
                    key: Key('add_quote_attachment_item_${item.id}'),
                    value: item.id,
                    groupValue: _selectedId,
                    title: Text(item.label),
                    onChanged: (value) => setState(() => _selectedId = value),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  void _onConfirm() {
    final kind = _kind;
    final id = _selectedId;
    if (kind == null || id == null) return;
    Navigator.of(context).pop((
      kind: kind,
      documentId: kind == QuoteAttachmentKind.letter ? null : id,
      templateRef: kind == QuoteAttachmentKind.letter ? id : null,
    ));
  }
}
