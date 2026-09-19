import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../financial_bloc.dart';
import '../financial_event.dart';
import 'financial_format_utils.dart';

/// Pièces jointes du devis (consentements, ordonnances, courriers) — lecture
/// seule côté patient (#7201). Extrait de `quote_detail_view.dart` (CLAUDE.md
/// plafond 700 lignes).
class QuoteAttachmentsList extends StatelessWidget {
  const QuoteAttachmentsList({super.key, required this.attachments});

  final List<QuoteAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NubiaCard(
        key: const Key('quote_attachments_card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.attach_file_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Pièces jointes',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final attachment in attachments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  key: Key('quote_attachment_${attachment.id}'),
                  children: [
                    Icon(_iconFor(attachment.kind),
                        size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _labelFor(attachment.kind),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(QuoteAttachmentKind kind) => switch (kind) {
        QuoteAttachmentKind.consent => Icons.verified_user_outlined,
        QuoteAttachmentKind.prescription => Icons.medication_outlined,
        QuoteAttachmentKind.letter => Icons.mail_outlined,
        QuoteAttachmentKind.other => Icons.insert_drive_file_outlined,
      };

  String _labelFor(QuoteAttachmentKind kind) => switch (kind) {
        QuoteAttachmentKind.consent => 'Consentement',
        QuoteAttachmentKind.prescription => 'Ordonnance',
        QuoteAttachmentKind.letter => 'Courrier',
        QuoteAttachmentKind.other => 'Autre document',
      };
}

/// Attestation d'information à lire puis signer avant de pouvoir signer le
/// devis (#7201/#7203) — verrou porté par `quote_detail_view.dart` qui
/// n'affiche le CTA « Signer le devis » que si [QuoteAttestation.isSigned].
class QuoteAttestationPanel extends StatefulWidget {
  const QuoteAttestationPanel({super.key, required this.attestation});

  final QuoteAttestation attestation;

  @override
  State<QuoteAttestationPanel> createState() => _QuoteAttestationPanelState();
}

class _QuoteAttestationPanelState extends State<QuoteAttestationPanel> {
  bool _hasRead = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final attestation = widget.attestation;

    if (attestation.isSigned) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: NubiaCard(
          key: const Key('quote_attestation_signed_card'),
          child: Row(
            children: [
              Icon(Icons.fact_check, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Attestation d'information signée le "
                  '${formatQuoteDate(attestation.signedAt!.toLocal())}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NubiaCard(
        key: const Key('quote_attestation_pending_card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Attestation d'information",
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(attestation.body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            NubiaCheckbox(
              key: const Key('quote_attestation_read_checkbox'),
              value: _hasRead,
              onChanged: (value) => setState(() => _hasRead = value),
              label: "J'ai lu et compris cette attestation.",
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: NubiaButton(
                key: const Key('btn_sign_attestation'),
                label: "Signer l'attestation",
                icon: Icons.draw,
                onPressed: _hasRead
                    ? () => context
                        .read<FinancialBloc>()
                        .add(const FinancialAttestationSignRequested())
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
