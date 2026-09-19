import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../quote_documents_cubit.dart';
import 'add_quote_attachment_dialog.dart';
import 'create_quote_attestation_dialog.dart';

/// Panneau « documents à joindre » (consentements, ordonnances, courriers)
/// + attestation d'information d'un devis (#7202/#7203), affiché sur le
/// détail devis praticien avant l'envoi au patient.
///
/// Doit être placée dans un `BlocProvider<QuoteDocumentsCubit>`.
class QuoteDocumentsSection extends StatefulWidget {
  const QuoteDocumentsSection({
    super.key,
    required this.quoteId,
    required this.patientId,
    required this.locked,
  });

  final String quoteId;
  final String patientId;

  /// Devis déjà signé (`409 quote_locked` côté API) : pièces jointes et
  /// attestation ne sont plus modifiables, affichage lecture seule.
  final bool locked;

  @override
  State<QuoteDocumentsSection> createState() => _QuoteDocumentsSectionState();
}

class _QuoteDocumentsSectionState extends State<QuoteDocumentsSection> {
  @override
  void initState() {
    super.initState();
    context.read<QuoteDocumentsCubit>().load(widget.quoteId, widget.patientId);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<QuoteDocumentsCubit, QuoteDocumentsState>(
      listenWhen: (previous, current) =>
          current is QuoteDocumentsLoaded && current.actionError != null,
      listener: (context, state) {
        final message = (state as QuoteDocumentsLoaded).actionError!;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            key: const Key('quote_documents_error_snackbar'),
            content: Text(message),
          ));
      },
      builder: (context, state) {
        if (state is QuoteDocumentsLoading) {
          return const NubiaSkeletonLoader(
            key: Key('quote_documents_loading'),
            height: 120,
            borderRadius: 12,
          );
        }
        if (state is QuoteDocumentsError) {
          return NubiaErrorWidget(
            key: const Key('quote_documents_error'),
            message: state.message,
            onRetry: () => context
                .read<QuoteDocumentsCubit>()
                .load(widget.quoteId, widget.patientId),
          );
        }
        final loaded = state as QuoteDocumentsLoaded;
        return NubiaCard(
          key: const Key('quote_documents_section'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AttachmentsPanel(
                quoteId: widget.quoteId,
                locked: widget.locked,
                state: loaded,
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              _AttestationPanel(
                quoteId: widget.quoteId,
                locked: widget.locked,
                state: loaded,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Pièces jointes
// ---------------------------------------------------------------------------

class _AttachmentsPanel extends StatelessWidget {
  const _AttachmentsPanel({
    required this.quoteId,
    required this.locked,
    required this.state,
  });

  final String quoteId;
  final bool locked;
  final QuoteDocumentsLoaded state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.attach_file_outlined, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Documents à joindre',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!locked)
              IconButton(
                key: const Key('quote_documents_add_button'),
                icon: state.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                tooltip: 'Ajouter une pièce jointe',
                onPressed: state.busy ? null : () => _onAdd(context),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (state.attachments.isEmpty)
          Text(
            'Aucune pièce jointe.',
            key: const Key('quote_attachments_empty'),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          Column(
            key: const Key('quote_attachments_list'),
            children: [
              for (final attachment in state.attachments)
                ListRow(
                  key: Key('quote_attachment_${attachment.id}'),
                  leading: Icon(_iconFor(attachment.kind), color: cs.primary),
                  title: _labelFor(attachment),
                  subtitle: _kindLabel(attachment.kind),
                  trailing: locked
                      ? null
                      : IconButton(
                          key: Key('quote_attachment_remove_${attachment.id}'),
                          icon: const Icon(Icons.close),
                          tooltip: 'Retirer',
                          onPressed: state.busy
                              ? null
                              : () => context
                                  .read<QuoteDocumentsCubit>()
                                  .removeAttachment(quoteId, attachment.id),
                        ),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _onAdd(BuildContext context) async {
    final cubit = context.read<QuoteDocumentsCubit>();
    final result = await showAddQuoteAttachmentDialog(
      context,
      consents: state.availableConsents,
      prescriptions: state.availablePrescriptions,
      letterTemplates: state.availableLetterTemplates,
      consentTemplates: state.availableConsentTemplates,
    );
    if (result == null) return;
    final consentTemplateId = result.consentTemplateId;
    if (consentTemplateId != null) {
      cubit.attachConsentTemplate(quoteId, consentTemplateId);
      return;
    }
    cubit.addAttachment(
      quoteId,
      kind: result.kind,
      documentId: result.documentId,
      templateRef: result.templateRef,
    );
  }

  String _labelFor(QuoteAttachment attachment) {
    final documentId = attachment.documentId;
    if (documentId != null) {
      final doc = _findDocument(state.availableConsents, documentId) ??
          _findDocument(state.availablePrescriptions, documentId);
      return doc?.filename ?? 'Document';
    }
    final templateRef = attachment.templateRef;
    if (templateRef != null) {
      for (final template in state.availableLetterTemplates) {
        if (template.id == templateRef) return template.name;
      }
      return 'Courrier';
    }
    return 'Pièce jointe';
  }

  PatientDocument? _findDocument(List<PatientDocument> docs, String id) {
    for (final doc in docs) {
      if (doc.id == id) return doc;
    }
    return null;
  }

  IconData _iconFor(QuoteAttachmentKind kind) => switch (kind) {
        QuoteAttachmentKind.consent => Icons.verified_user_outlined,
        QuoteAttachmentKind.prescription => Icons.medication_outlined,
        QuoteAttachmentKind.letter => Icons.mail_outlined,
        QuoteAttachmentKind.other => Icons.insert_drive_file_outlined,
      };

  String _kindLabel(QuoteAttachmentKind kind) => switch (kind) {
        QuoteAttachmentKind.consent => 'Consentement',
        QuoteAttachmentKind.prescription => 'Ordonnance',
        QuoteAttachmentKind.letter => 'Courrier',
        QuoteAttachmentKind.other => 'Autre',
      };
}

// ---------------------------------------------------------------------------
// Attestation d'information
// ---------------------------------------------------------------------------

class _AttestationPanel extends StatelessWidget {
  const _AttestationPanel({
    required this.quoteId,
    required this.locked,
    required this.state,
  });

  final String quoteId;
  final bool locked;
  final QuoteDocumentsLoaded state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final attestation = state.attestation;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.fact_check_outlined, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Attestation d'information",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              _StatusChip(attestation: attestation),
            ],
          ),
        ),
        if (!locked && (attestation == null || attestation.isSigned))
          NubiaButton(
            key: const Key('quote_attestation_generate_button'),
            label: 'Générer',
            variant: NubiaButtonVariant.secondary,
            size: NubiaButtonSize.sm,
            isLoading: state.busy,
            onPressed: state.busy ? null : () => _onGenerate(context),
          ),
      ],
    );
  }

  Future<void> _onGenerate(BuildContext context) async {
    final cubit = context.read<QuoteDocumentsCubit>();
    final body = await showCreateQuoteAttestationDialog(context);
    if (body == null) return;
    cubit.createAttestation(quoteId, body);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.attestation});

  final QuoteAttestation? attestation;

  @override
  Widget build(BuildContext context) {
    if (attestation == null) {
      return const StatusPill(
        key: Key('quote_attestation_status_none'),
        label: 'Non déposée',
        variant: StatusPillVariant.neutral,
      );
    }
    if (attestation!.isSigned) {
      return StatusPill(
        key: const Key('quote_attestation_status_signed'),
        label: 'Signée le ${_formatDate(attestation!.signedAt!)}',
        variant: StatusPillVariant.success,
      );
    }
    return const StatusPill(
      key: Key('quote_attestation_status_pending'),
      label: 'En attente de signature',
      variant: StatusPillVariant.warning,
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}
