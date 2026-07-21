import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

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
    final style = QuoteStatusStyle.of(quote.status);
    final canSign = quote.canSign;
    final canPay = quote.status == QuoteStatus.signed && quote.depositCents > 0;
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
                // Badge statut centré (mockup wedge).
                Center(
                  child: StatusPill(label: style.label, variant: style.variant),
                ),
                const SizedBox(height: 16),
                // En-tête montant + bandeau reste à charge.
                AmountHeader(
                  label: 'Total du plan de soins',
                  amount: formatQuoteCents(quote.totalCents),
                  caption: quote.practitionerName.isNotEmpty
                      ? quote.practitionerName
                      : 'Devis du ${formatQuoteDate(quote.createdAt)}',
                  remainingLabel: 'Reste à charge',
                  remainingAmount: formatQuoteCents(quote.patientShareCents),
                  remainingCaption: 'après remboursements',
                ),
                const SizedBox(height: 20),
                if (hasRac0Alternative) ...[
                  const _Rac0AlternativeBanner(),
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
                if (canPay) _DepositCard(quote: quote),
                const _ReassuranceRow(),
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
            NubiaButton(
              key: const Key('btn_back'),
              label: 'Retour à la liste',
              variant: NubiaButtonVariant.tertiary,
              size: NubiaButtonSize.lg,
              onPressed: () => context
                  .read<FinancialBloc>()
                  .add(const FinancialBackToList()),
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
/// classifié `modere` (#4061).
class _Rac0AlternativeBanner extends StatelessWidget {
  const _Rac0AlternativeBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return NubiaCard(
      key: const Key('rac0_alternative_banner'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: tokens.primarySubtleFg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alternative reste à charge zéro disponible',
                  style:
                      theme.textTheme.labelLarge?.copyWith(color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  'Un ou plusieurs actes de ce devis disposent d\'une option '
                  '100% Santé (RAC 0). Parlez-en à votre praticien.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.label,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    if (item.panierSante != PanierSante.unknown &&
                        item.panierSante != PanierSante.horsNomenclature) ...[
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
                  const SizedBox(height: 2),
                  Text(
                    'Solde à régler à la pose',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
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

/// Bandeau de réassurance : signature électronique sécurisée (eIDAS).
class _ReassuranceRow extends StatelessWidget {
  const _ReassuranceRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 17, color: cs.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Signature électronique sécurisée ',
                children: const [
                  TextSpan(
                    text: '(eIDAS)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' · devis chiffré et horodaté'),
                ],
              ),
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
