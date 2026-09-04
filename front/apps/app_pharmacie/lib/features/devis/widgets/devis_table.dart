import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../devis_bloc.dart';
import '../quote_delay.dart';
import '../quote_status.dart';

/// Largeurs des colonnes du tableau devis d'officine (design-v2, #6454) —
/// grille maquette `Devis | Patient | Contenu | Total | Statut | Action`.
/// Partagée entre [DevisTableHeader] et [DevisTableRow] pour rester alignées.
class _DevisColumns {
  const _DevisColumns._();

  static const double gap = 12;
  static const double devis = 92;
  static const double total = 84;
  // 106 px (proportion de la grille maquette) ne suffit pas au `StatusPill`
  // du libellé le plus long, « Brouillon », sans le faire déborder — même
  // ajustement que le tableau devis secrétariat (widgets/devis_table.dart).
  static const double statut = 150;
  static const double action = 116;
}

class DevisTableHeader extends StatelessWidget {
  const DevisTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: tokens.textTertiary,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          SizedBox(width: _DevisColumns.devis, child: Text('Devis', style: style)),
          const SizedBox(width: _DevisColumns.gap),
          Expanded(child: Text('Patient', style: style)),
          const SizedBox(width: _DevisColumns.gap),
          Expanded(child: Text('Contenu', style: style)),
          const SizedBox(width: _DevisColumns.gap),
          SizedBox(
            width: _DevisColumns.total,
            child: Text('Total', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: _DevisColumns.gap),
          SizedBox(width: _DevisColumns.statut, child: Text('Statut', style: style)),
          const SizedBox(width: _DevisColumns.gap),
          SizedBox(
            width: _DevisColumns.action,
            child: Text('Action', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// Résumé de la colonne Contenu : libellé du premier article, et sous-ligne
/// « + N autres articles » (ou « 1 article » si le devis n'en a qu'un).
({String main, String sub}) _contentSummary(PharmacyQuote quote) {
  final first = quote.items.isEmpty ? '' : quote.items.first.label;
  final rest = quote.items.length - 1;
  final sub = rest <= 0
      ? '1 article'
      : rest == 1
          ? '+ 1 autre article'
          : '+ $rest autres articles';
  return (main: first, sub: sub);
}

/// Ligne du tableau devis d'officine (design-v2, #6454) : colonnes Devis
/// (n° + date de création), Patient (avatar + nom + délai), Contenu (premier
/// article résumé), Total (colonne dédiée — plus de calcul mental ligne à
/// ligne, écart #3 de la QA), Statut, Action. La ligne entière est cliquable
/// (ouvre le volet de détail) sauf le bouton d'action, qui garde son
/// comportement propre (écart #2).
class DevisTableRow extends StatelessWidget {
  const DevisTableRow({
    super.key,
    required this.quote,
    this.onTap,
    this.active = false,
    this.actionLoading = false,
  });

  final PharmacyQuote quote;
  final VoidCallback? onTap;
  final bool active;
  final bool actionLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final textTheme = theme.textTheme;
    final delay = quoteDelayOf(quote);
    final delayColor = switch (delay.tone) {
      QuoteDelayTone.neutral => tokens.textTertiary,
      QuoteDelayTone.soon => tokens.warningFg,
      QuoteDelayTone.late => tokens.dangerFg,
    };
    final content = _contentSummary(quote);

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _DevisColumns.devis,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quote.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontFeatures: tabularFigures,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatShortDate(quote.createdAt),
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textTertiary,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _DevisColumns.gap),
            Expanded(
              child: Row(
                children: [
                  NubiaAvatar(
                    initials: NubiaInitials.of(quote.patientDisplayName ?? '?'),
                    radius: 16,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quote.patientDisplayName ?? 'Patient',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall,
                        ),
                        Text(
                          delay.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(color: delayColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _DevisColumns.gap),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    content.main,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium,
                  ),
                  Text(
                    content.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _DevisColumns.gap),
            SizedBox(
              width: _DevisColumns.total,
              child: Text(
                NubiaMoney.formatCents(quote.totalCents),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            const SizedBox(width: _DevisColumns.gap),
            SizedBox(
              width: _DevisColumns.statut,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: quoteStatusLabel(quote.status),
                  variant: quoteStatusVariant(quote.status),
                  icon: quoteStatusIcon(quote.status),
                ),
              ),
            ),
            const SizedBox(width: _DevisColumns.gap),
            SizedBox(
              width: _DevisColumns.action,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _DevisRowAction(
                    quote: quote,
                    active: active,
                    loading: actionLoading,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: active ? NubiaColors.brand50 : Colors.transparent,
          foregroundDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: active ? NubiaColors.brand700 : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('quote_${quote.id}'),
              onTap: onTap,
              child: row,
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
      ],
    );
  }
}

/// Bouton d'action contextuel au statut (écart #5, QA #6454) : un devis
/// « Accepté » a désormais une action — « Préparer », qui renvoie vers la
/// commande d'origine où le pharmacien fait progresser la préparation
/// (`AcceptPharmacyOrderUseCase`/`MarkPharmacyOrderReadyUseCase`), comme les
/// actions déjà existantes de « Refusé »/« Expiré ». Aucun nouveau statut de
/// devis n'est inventé : le cycle `draft → sent → accepted/refused/expired`
/// reste inchangé.
class _DevisRowAction extends StatelessWidget {
  const _DevisRowAction({
    required this.quote,
    required this.active,
    required this.loading,
  });

  final PharmacyQuote quote;
  final bool active;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final variant =
        active ? NubiaButtonVariant.primary : NubiaButtonVariant.secondary;
    switch (quote.status) {
      case PharmacyQuoteStatus.draft:
        return NubiaButton(
          key: Key('quote_send_${quote.id}'),
          label: 'Envoyer',
          icon: Icons.send,
          size: NubiaButtonSize.sm,
          variant: variant,
          isLoading: loading,
          onPressed: loading
              ? null
              : () => context
                  .read<PharmacyDevisBloc>()
                  .add(PharmacyDevisSendRequested(quote.id)),
        );
      case PharmacyQuoteStatus.sent:
        return NubiaButton(
          key: Key('quote_remind_${quote.id}'),
          label: 'Relancer',
          icon: Icons.notifications_active_outlined,
          size: NubiaButtonSize.sm,
          variant: variant,
          isLoading: loading,
          onPressed: loading
              ? null
              : () => context
                  .read<PharmacyDevisBloc>()
                  .add(PharmacyDevisRemindRequested(quote.id)),
        );
      case PharmacyQuoteStatus.accepted:
        if (quote.orderId == null) return const SizedBox.shrink();
        return NubiaButton(
          key: Key('quote_prepare_${quote.id}'),
          label: 'Préparer',
          icon: Icons.inventory,
          size: NubiaButtonSize.sm,
          variant: variant,
          onPressed: () => context.go('/orders/${quote.orderId}'),
        );
      case PharmacyQuoteStatus.expired:
        if (quote.orderId == null) return const SizedBox.shrink();
        return NubiaButton(
          key: Key('quote_reissue_${quote.id}'),
          label: 'Réémettre',
          icon: Icons.refresh,
          size: NubiaButtonSize.sm,
          variant: variant,
          onPressed: () => context.go('/orders/${quote.orderId}'),
        );
      case PharmacyQuoteStatus.refused:
        if (quote.orderId == null) return const SizedBox.shrink();
        return NubiaButton(
          key: Key('quote_view_${quote.id}'),
          label: 'Voir',
          icon: Icons.visibility,
          size: NubiaButtonSize.sm,
          variant: NubiaButtonVariant.tertiary,
          onPressed: () => context.go('/orders/${quote.orderId}'),
        );
    }
  }
}

String _formatShortDate(DateTime d) {
  final local = d.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}';
}
