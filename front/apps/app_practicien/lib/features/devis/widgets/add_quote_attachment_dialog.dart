import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Résultat renvoyé par [showAddQuoteAttachmentDialog] à la validation.
/// Exactement un de `documentId`/`templateRef`/`consentTemplateId` est
/// renseigné. `documentId`/`templateRef` respectent la contrainte XOR de
/// `POST /v1/cabinet/quotes/:id/attachments` (`quote_attachment_source_xor`) ;
/// `consentTemplateId` (#7198) est résolu en `documentId` par
/// `QuoteDocumentsCubit.attachConsentTemplate` avant l'appel API — le
/// modèle est d'abord rendu pour ce devis, puis le document obtenu est
/// attaché.
typedef AddQuoteAttachmentResult = ({
  QuoteAttachmentKind kind,
  String? documentId,
  String? templateRef,
  String? consentTemplateId,
});

/// Choix d'une pièce à joindre à l'envoi d'un devis (#7202/#7203) : un
/// consentement (déjà numérisé dans le dossier patient, ou généré à partir
/// d'un modèle, #7198) ou une ordonnance déjà numérisée, ou un modèle de
/// courrier.
Future<AddQuoteAttachmentResult?> showAddQuoteAttachmentDialog(
  BuildContext context, {
  required List<PatientDocument> consents,
  required List<PatientDocument> prescriptions,
  required List<LetterTemplate> letterTemplates,
  List<ConsentTemplate> consentTemplates = const [],
}) {
  return showDialog<AddQuoteAttachmentResult>(
    context: context,
    builder: (_) => AddQuoteAttachmentDialog(
      consents: consents,
      prescriptions: prescriptions,
      letterTemplates: letterTemplates,
      consentTemplates: consentTemplates,
    ),
  );
}

class AddQuoteAttachmentDialog extends StatefulWidget {
  const AddQuoteAttachmentDialog({
    super.key,
    required this.consents,
    required this.prescriptions,
    required this.letterTemplates,
    this.consentTemplates = const [],
  });

  final List<PatientDocument> consents;
  final List<PatientDocument> prescriptions;
  final List<LetterTemplate> letterTemplates;
  final List<ConsentTemplate> consentTemplates;

  @override
  State<AddQuoteAttachmentDialog> createState() =>
      _AddQuoteAttachmentDialogState();
}

class _AddQuoteAttachmentDialogState extends State<AddQuoteAttachmentDialog> {
  QuoteAttachmentKind? _kind;
  String? _selectedId;
  bool _selectedIsConsentTemplate = false;

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
    if (kind == QuoteAttachmentKind.consent) {
      return _buildConsentPicker();
    }

    final items = switch (kind) {
      QuoteAttachmentKind.prescription =>
        widget.prescriptions.map((d) => (id: d.id, label: d.filename)).toList(),
      QuoteAttachmentKind.letter =>
        widget.letterTemplates.map((t) => (id: t.id, label: t.name)).toList(),
      QuoteAttachmentKind.consent || QuoteAttachmentKind.other =>
        const <({String id, String label})>[],
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backButton(),
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
                    onChanged: (value) => setState(() {
                      _selectedId = value;
                      _selectedIsConsentTemplate = false;
                    }),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Consentement : documents déjà numérisés dans le dossier patient, ou
  /// modèles (catalogue/cabinet, #7198) à rendre pour ce devis.
  Widget _buildConsentPicker() {
    final hasAny =
        widget.consents.isNotEmpty || widget.consentTemplates.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backButton(),
        if (!hasAny)
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
                for (final doc in widget.consents)
                  RadioListTile<String>(
                    key: Key('add_quote_attachment_item_${doc.id}'),
                    value: doc.id,
                    groupValue: _selectedId,
                    title: Text(doc.filename),
                    onChanged: (value) => setState(() {
                      _selectedId = value;
                      _selectedIsConsentTemplate = false;
                    }),
                  ),
                if (widget.consentTemplates.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('Depuis un modèle'),
                  ),
                  for (final template in widget.consentTemplates)
                    RadioListTile<String>(
                      key: Key('add_quote_attachment_template_${template.id}'),
                      value: template.id,
                      groupValue: _selectedId,
                      title: Text(template.title),
                      onChanged: (value) => setState(() {
                        _selectedId = value;
                        _selectedIsConsentTemplate = true;
                      }),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _backButton() {
    return TextButton.icon(
      onPressed: () => setState(() {
        _kind = null;
        _selectedId = null;
        _selectedIsConsentTemplate = false;
      }),
      icon: const Icon(Icons.arrow_back, size: 16),
      label: const Text('Changer de type'),
    );
  }

  void _onConfirm() {
    final kind = _kind;
    final id = _selectedId;
    if (kind == null || id == null) return;
    Navigator.of(context).pop((
      kind: kind,
      documentId: kind == QuoteAttachmentKind.letter ||
              (kind == QuoteAttachmentKind.consent &&
                  _selectedIsConsentTemplate)
          ? null
          : id,
      templateRef: kind == QuoteAttachmentKind.letter ? id : null,
      consentTemplateId: kind == QuoteAttachmentKind.consent &&
              _selectedIsConsentTemplate
          ? id
          : null,
    ));
  }
}
