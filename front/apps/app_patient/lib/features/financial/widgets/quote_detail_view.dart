import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../../router/app_router.dart';
import '../financial_bloc.dart';
import '../financial_event.dart';
import '../financial_state.dart';
import 'financial_format_utils.dart';

/// Détail d'un devis (actes, panier 100% Santé, acompte, signature) —
/// extrait de `financial_page.dart` (#4061, CLAUDE.md plafond 700 lignes).

class QuoteDetailView extends StatefulWidget {
  const QuoteDetailView({super.key, required this.state});

  final FinancialQuoteDetail state;

  @override
  State<QuoteDetailView> createState() => _QuoteDetailViewState();
}

class _QuoteDetailViewState extends State<QuoteDetailView> {
  late final String _payKey =
      '${widget.state.quote.id}-pay-${DateTime.now().microsecondsSinceEpoch}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final quote = widget.state.quote;
    final canSign = quote.canSign;
    final canPay = quote.status == QuoteStatus.signed && quote.depositCents > 0;
    final canDownload =
        quote.status == QuoteStatus.signed && quote.documentId != null;
    // Obligation conventionnelle de présenter l'alternative RAC 0 (#4061) :
    // dès qu'une ligne est classifiée `modere`, une option 100% Santé (RAC 0)
    // existe forcément pour ce même type d'acte — le praticien doit pouvoir
    // en discuter avec le patient, même si l'API ne référence pas encore le
    // code CCAM équivalent précis (cf. commentaire migration 0161).
    final hasRac0Alternative =
        quote.items.any((i) => i.panierSante == PanierSante.modere);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // En-tête montant : le montant héros suit le statut du devis
                // (total avant signature, reste à charge après — #5235). Le
                // détail du calcul Total → reste à charge est porté par la
                // barre de ventilation ci-dessous (#5234).
                if (quote.status == QuoteStatus.signed)
                  AmountHeader(
                    label: 'Reste à votre charge',
                    amount: formatQuoteCents(quote.patientShareCents),
                    caption:
                        'sur ${formatQuoteCents(quote.totalCents)} · après remboursements',
                  )
                else
                  AmountHeader(
                    label: 'Total du plan de soins',
                    amount: formatQuoteCents(quote.totalCents),
                    caption: quote.practitionerName.isNotEmpty
                        ? '${quote.practitionerName} · devis du ${formatQuoteDate(quote.createdAt)}'
                        : 'Devis du ${formatQuoteDate(quote.createdAt)}',
                  ),
                const SizedBox(height: 20),
                VentilationBar(
                  amoCents: quote.items.amoShareTotalCents,
                  amcCents: quote.items.amcShareTotalCents,
                  racCents: quote.patientShareCents,
                  racLabel: 'Reste à votre charge',
                ),
                const SizedBox(height: 12),
                if (hasRac0Alternative) ...[
                  _Rac0AlternativeBanner(
                    count: quote.items
                        .where((i) => i.panierSante == PanierSante.modere)
                        .length,
                  ),
                  const SizedBox(height: 12),
                ],
                // Détail des actes.
                NubiaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Détail des actes',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      if (quote.items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Le détail des actes sera disponible sur le devis signé.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        )
                      else
                        for (int i = 0; i < quote.items.length; i++)
                          _LineItemRow(
                            item: quote.items[i],
                            showDivider: i > 0,
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (canPay) ...[
                  _DepositCard(quote: quote),
                  _PaymentSchedule(quote: quote),
                ],
                _ReassuranceRow(canPay: canPay),
              ],
            ),
          ),
        ),
        // CTA sticky.
        _StickyActions(
          children: [
            if (canSign)
              NubiaButton(
                key: const Key('btn_sign'),
                label: 'Signer le devis',
                icon: Icons.edit_outlined,
                size: NubiaButtonSize.lg,
                onPressed: () => context
                    .read<FinancialBloc>()
                    .add(const FinancialSignatureRequested()),
              ),
            if (canPay)
              NubiaButton(
                key: const Key('btn_pay'),
                label: 'Payer l\'acompte',
                icon: Icons.lock_outline,
                size: NubiaButtonSize.lg,
                onPressed: () => context
                    .read<FinancialBloc>()
                    .add(FinancialPaymentRequested(idempotencyKey: _payKey)),
              ),
            if (canDownload)
              NubiaButton(
                key: const Key('btn_download'),
                label: 'Télécharger le devis signé',
                variant: NubiaButtonVariant.secondary,
                onPressed: () => context
                    .read<FinancialBloc>()
                    .add(const FinancialDownloadRequested()),
              ),
          ],
        ),
      ],
    );
  }
}

/// Badge panier 100% Santé (RAC 0 / modéré / libre) affiché par ligne d'acte.
/// Rien n'est affiché si non classifié (`unknown`/`horsNomenclature`) : une
/// classification absente ne doit jamais être présentée comme une valeur
/// (#4055/#4061).
class PanierBadge extends StatelessWidget {
  const PanierBadge({super.key, required this.panier});

  final PanierSante panier;

  @override
  Widget build(BuildContext context) {
    final style = switch (panier) {
      PanierSante.rac0 => ('RAC 0', StatusPillVariant.success),
      PanierSante.modere => ('Modéré', StatusPillVariant.warning),
      PanierSante.libre => ('Libre', StatusPillVariant.info),
      PanierSante.horsNomenclature || PanierSante.unknown => (null, null),
    };
    final (label, variant) = style;
    if (label == null || variant == null) return const SizedBox.shrink();
    return StatusPill(
        key: Key('panier_badge_${panier.name}'),
        label: label,
        variant: variant);
  }
}

/// Encart obligatoire (obligation conventionnelle) : rappelle qu'une
/// alternative reste-à-charge zéro existe dès qu'un acte du devis est
/// classifié `modere` (#4061). Teinté `warning` avec action « En parler au
/// praticien » vers la messagerie, au lieu d'une phrase sans issue (#5237,
/// maquette `design/v2-screens/patient-facturation.png`).
class _Rac0AlternativeBanner extends StatelessWidget {
  const _Rac0AlternativeBanner({required this.count});

  final int count;

  static const _titleColor = Color(0xFF78350F);
  static const _bodyColor = Color(0xFF92400E);
  static const _chipBorderColor = Color(0xFFFCD34D);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;

    return Container(
      key: const Key('rac0_alternative_banner'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        border: Border.all(color: NubiaColors.warningBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.savings, size: 20, color: tokens.warningFg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alternative reste à charge zéro disponible',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: _titleColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count <= 1
                      ? 'Un acte de ce devis a une option 100 % Santé.'
                      : '$count actes de ce devis ont une option 100 % Santé.',
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: _bodyColor),
                ),
                const SizedBox(height: 10),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const Key('rac0_alternative_banner_cta'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => context.push(AppRouter.messaging),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _chipBorderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble,
                              size: 14, color: _titleColor),
                          const SizedBox(width: 6),
                          Text(
                            'En parler au praticien',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _titleColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({required this.item, required this.showDivider});

  final QuoteLineItem item;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider)
          Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (item.panierSante != PanierSante.unknown &&
                            item.panierSante !=
                                PanierSante.horsNomenclature) ...[
                          const SizedBox(width: 8),
                          PanierBadge(panier: item.panierSante),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatQuoteCents(item.totalCents),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
              // Ventilation AMO/AMC (#4063) : pas de sous-ligne si les deux
              // parts sont nulles (rien renseigné côté back).
              if (item.amoShareCents != 0 || item.amcShareCents != 0) ...[
                const SizedBox(height: 2),
                Text(
                  [
                    if (item.amoShareCents != 0)
                      'Part AMO : ${formatQuoteCents(item.amoShareCents)}',
                    if (item.amcShareCents != 0)
                      'Part AMC : ${formatQuoteCents(item.amcShareCents)}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Carte « acompte à régler aujourd'hui » (visible quand le devis est signé).
class _DepositCard extends StatelessWidget {
  const _DepositCard({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NubiaCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tokens.primarySubtleBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.euro, size: 22, color: tokens.primarySubtleFg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acompte à régler',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: cs.onSurface),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatQuoteCents(quote.depositCents),
              style: theme.textTheme.titleLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Échéancier de paiement (acompte aujourd'hui, solde à la pose) — remplace
/// la phrase « Solde à régler à la pose » de `_DepositCard` par une
/// décomposition vérifiable des deux jalons (#5238). La somme des deux
/// montants affichés égale toujours `quote.patientShareCents`.
///
/// Aucun champ `installmentDate` n'existe côté domaine aujourd'hui : on
/// dégrade proprement en omettant la date plutôt que d'en inventer une.
class _PaymentSchedule extends StatelessWidget {
  const _PaymentSchedule({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final balanceCents = quote.patientShareCents - quote.depositCents;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NubiaCard(
        key: const Key('payment_schedule'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PaymentScheduleStep(
              key: const Key('payment_schedule_step_deposit'),
              dotColor: NubiaColors.brand600,
              label: 'Aujourd\'hui · acompte',
              amount: formatQuoteCents(quote.depositCents),
              showConnector: true,
            ),
            _PaymentScheduleStep(
              key: const Key('payment_schedule_step_balance'),
              dotColor: NubiaColors.n300,
              label: 'À la pose · solde',
              amount: formatQuoteCents(balanceCents),
              showConnector: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// Un jalon de l'échéancier : puce à gauche (pleine émeraude pour l'acompte,
/// grise pour le solde à venir), reliée au jalon suivant par un connecteur
/// vertical fin quand [showConnector] est vrai.
class _PaymentScheduleStep extends StatelessWidget {
  const _PaymentScheduleStep({
    super.key,
    required this.dotColor,
    required this.label,
    required this.amount,
    required this.showConnector,
  });

  final Color dotColor;
  final String label;
  final String amount;
  final bool showConnector;

  static const _dotSize = 10.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              const SizedBox(height: 4),
              Container(
                width: _dotSize,
                height: _dotSize,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              if (showConnector)
                Expanded(
                  child: Container(width: 2, color: tokens.borderSubtle),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showConnector ? 16 : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: cs.onSurface),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    amount,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
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

/// Bandeau de réassurance : eIDAS avant signature, Stripe devant un paiement
/// (#5242). Un seul bandeau à la fois, selon l'action en cours.
class _ReassuranceRow extends StatelessWidget {
  const _ReassuranceRow({required this.canPay});

  final bool canPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    final TextSpan textSpan = canPay
        ? const TextSpan(
            text: 'Paiement sécurisé Stripe · ',
            children: [
              TextSpan(
                text: 'aucune donnée bancaire',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: ' conservée par le cabinet'),
            ],
          )
        : const TextSpan(
            text: 'Signature électronique sécurisée ',
            children: [
              TextSpan(
                text: '(eIDAS)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: ' · devis chiffré et horodaté'),
            ],
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 17, color: cs.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              textSpan,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: tokens.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre d'actions collée en bas de l'écran (CTA sticky).
class _StickyActions extends StatelessWidget {
  const _StickyActions({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(const SizedBox(height: 8));
      spaced.add(children[i]);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced,
          ),
        ),
      ),
    );
  }
}
