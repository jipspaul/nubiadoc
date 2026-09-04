import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../devis_bloc.dart';
import '../quote_status.dart';
import 'quote_timeline.dart';

/// Volet de détail d'un devis d'officine (design-v2, écart #2 de la QA
/// #6454) : ouvert au clic sur une ligne du tableau. Le devis est déjà
/// chargé en mémoire (`PharmacyDevisLoaded.quotes`) — pas de requête réseau
/// supplémentaire, contrairement au volet secrétariat qui recharge le
/// détail via son propre bloc.
class DevisDetailSheet extends StatelessWidget {
  const DevisDetailSheet({
    super.key,
    required this.quote,
    required this.onClose,
    this.sending = false,
  });

  final PharmacyQuote quote;
  final VoidCallback onClose;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    quote.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontFeatures: tabularFigures,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  label: quoteStatusLabel(quote.status),
                  variant: quoteStatusVariant(quote.status),
                  icon: quoteStatusIcon(quote.status),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('devis_sheet_close'),
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      NubiaAvatar(
                        initials:
                            NubiaInitials.of(quote.patientDisplayName ?? '?'),
                        radius: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              quote.patientDisplayName ?? 'Patient',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'créé le ${_formatDate(quote.createdAt)}',
                              style: textTheme.bodySmall?.copyWith(
                                color: tokens.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _ArticlesSection(quote: quote),
                  const SizedBox(height: 16),
                  PharmacyQuoteTimeline(quote: quote),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                _DevisSheetPrimaryAction(quote: quote, sending: sending),
                const SizedBox(height: 8),
                NubiaButton(
                  key: Key('quote_edit_${quote.id}'),
                  label: 'Modifier le devis',
                  icon: Icons.edit,
                  variant: NubiaButtonVariant.secondary,
                  size: NubiaButtonSize.lg,
                  // Aucune modification de devis d'officine n'existe côté
                  // domaine/API (pas d'`UpdatePharmacyQuoteUseCase`) : CTA
                  // visible mais désactivé plutôt qu'un comportement
                  // inventé — même choix que le bouton « Appeler » du volet
                  // secrétariat (`_DevisSheetBody`, app_secretariat).
                  onPressed: null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DevisSheetPrimaryAction extends StatelessWidget {
  const _DevisSheetPrimaryAction({required this.quote, required this.sending});

  final PharmacyQuote quote;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    switch (quote.status) {
      case PharmacyQuoteStatus.draft:
        return NubiaButton(
          key: Key('quote_sheet_send_${quote.id}'),
          label: 'Envoyer au patient',
          icon: Icons.send_outlined,
          size: NubiaButtonSize.lg,
          isLoading: sending,
          onPressed: sending
              ? null
              : () => context
                  .read<PharmacyDevisBloc>()
                  .add(PharmacyDevisSendRequested(quote.id)),
        );
      case PharmacyQuoteStatus.sent:
        return NubiaButton(
          key: Key('quote_sheet_remind_${quote.id}'),
          label: 'Relancer le patient',
          icon: Icons.notifications_active_outlined,
          size: NubiaButtonSize.lg,
          isLoading: sending,
          onPressed: sending
              ? null
              : () => context
                  .read<PharmacyDevisBloc>()
                  .add(PharmacyDevisRemindRequested(quote.id)),
        );
      case PharmacyQuoteStatus.accepted:
        if (quote.orderId == null) return const SizedBox.shrink();
        return NubiaButton(
          key: Key('quote_sheet_prepare_${quote.id}'),
          label: 'Préparer',
          icon: Icons.inventory,
          size: NubiaButtonSize.lg,
          onPressed: () => context.go('/orders/${quote.orderId}'),
        );
      case PharmacyQuoteStatus.expired:
        if (quote.orderId == null) return const SizedBox.shrink();
        return NubiaButton(
          key: Key('quote_sheet_reissue_${quote.id}'),
          label: 'Réémettre',
          icon: Icons.refresh,
          size: NubiaButtonSize.lg,
          onPressed: () => context.go('/orders/${quote.orderId}'),
        );
      case PharmacyQuoteStatus.refused:
        if (quote.orderId == null) return const SizedBox.shrink();
        return NubiaButton(
          key: Key('quote_sheet_view_${quote.id}'),
          label: 'Voir la commande',
          icon: Icons.visibility,
          variant: NubiaButtonVariant.secondary,
          size: NubiaButtonSize.lg,
          onPressed: () => context.go('/orders/${quote.orderId}'),
        );
    }
  }
}

/// Section « Articles » (écart #2, QA #6454) : quantité, libellé et **prix
/// unitaire** par ligne — la maquette exige le prix unitaire pour éviter au
/// lecteur de multiplier de tête (écart #3), donnée déjà présente sur
/// `PharmacyQuoteItem.unitPriceCents`.
class _ArticlesSection extends StatelessWidget {
  const _ArticlesSection({required this.quote});

  final PharmacyQuote quote;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Articles', style: textTheme.titleSmall),
              const Spacer(),
              Text(
                '${quote.items.length} ligne${quote.items.length > 1 ? 's' : ''}',
                style: textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in quote.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${item.quantity}',
                      textAlign: TextAlign.right,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item.label, style: textTheme.bodyMedium),
                  ),
                  Text(
                    NubiaMoney.formatCents(item.unitPriceCents),
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
          Divider(height: 20, color: tokens.borderSubtle),
          Row(
            children: [
              Text(
                'Total',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                NubiaMoney.formatCents(quote.totalCents),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _RefundNotice(warningBg: tokens.warningBg, warningFg: tokens.warningFg),
        ],
      ),
    );
  }
}

/// Encart « Hors remboursement » (verbatim maquette design-v2) : les
/// articles d'un devis d'officine sont des produits de confort, sans part
/// AMO ni AMC.
class _RefundNotice extends StatelessWidget {
  const _RefundNotice({required this.warningBg, required this.warningFg});

  final Color warningBg;
  final Color warningFg;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('devis_sheet_refund_notice'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: warningBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info, size: 16, color: warningFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 11.5, color: warningFg, height: 1.4),
                children: const [
                  TextSpan(
                    text: 'Hors remboursement. ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: 'Ces articles de confort ne donnent lieu à aucune '
                        "part AMO ni AMC — le patient règle l'intégralité.",
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime d) {
  final local = d.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}
