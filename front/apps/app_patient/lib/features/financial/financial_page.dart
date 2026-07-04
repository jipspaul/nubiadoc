import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'financial_bloc.dart';
import 'financial_event.dart';
import 'financial_state.dart';

/// Wedge financier : liste de devis → détail → signature Yousign → paiement acompte.
///
/// Écran premium du parcours patient : cartes soignées (design system Nubia),
/// montants en chiffres tabulaires, bandeau reste-à-charge, CTA sticky et reçu
/// de paiement.
///
/// Doit être placé sous un [BlocProvider<FinancialBloc>] (fourni par le router
/// ou le parent).
class FinancialPage extends StatelessWidget {
  const FinancialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FinancialBloc, FinancialState>(
      builder: (context, state) {
        if (state is FinancialInitial || state is FinancialLoading) {
          return const _LoadingView(key: Key('financial_loading'));
        }
        if (state is FinancialError) {
          return NubiaErrorWidget(
            key: const Key('financial_error'),
            message: state.message,
            onRetry: () => context
                .read<FinancialBloc>()
                .add(const FinancialLoadRequested()),
          );
        }
        if (state is FinancialLoaded) {
          return _QuoteListView(state: state);
        }
        if (state is FinancialQuoteDetail) {
          return _QuoteDetailView(state: state);
        }
        if (state is FinancialSignatureInProgress) {
          return _SignatureView(state: state);
        }
        if (state is FinancialPaymentInProgress) {
          return const _PaymentLoadingView(
              key: Key('financial_payment_loading'));
        }
        if (state is FinancialPaymentSuccess) {
          return _PaymentSuccessView(state: state);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    // Skeleton de trois cartes plutôt qu'un spinner nu (§2 principes design).
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: const [
        _QuoteSkeletonCard(),
        SizedBox(height: 12),
        _QuoteSkeletonCard(),
        SizedBox(height: 12),
        _QuoteSkeletonCard(),
      ],
    );
  }
}

class _QuoteSkeletonCard extends StatelessWidget {
  const _QuoteSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: NubiaSkeletonLoader(height: 16, width: 160)),
              SizedBox(width: 12),
              NubiaSkeletonLoader(height: 20, width: 64),
            ],
          ),
          SizedBox(height: 12),
          NubiaSkeletonLoader(height: 28, width: 120),
          SizedBox(height: 10),
          NubiaSkeletonLoader(height: 12, width: 90),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Liste des devis
// ---------------------------------------------------------------------------

class _QuoteListView extends StatefulWidget {
  const _QuoteListView({required this.state});

  final FinancialLoaded state;

  @override
  State<_QuoteListView> createState() => _QuoteListViewState();
}

class _QuoteListViewState extends State<_QuoteListView> {
  Completer<void>? _refreshCompleter;

  @override
  Widget build(BuildContext context) {
    return BlocListener<FinancialBloc, FinancialState>(
      listener: (context, state) {
        if (state is FinancialLoaded || state is FinancialError) {
          _refreshCompleter?.complete();
          _refreshCompleter = null;
        }
      },
      child: RefreshIndicator(
        onRefresh: () {
          _refreshCompleter = Completer<void>();
          context.read<FinancialBloc>().add(const FinancialLoadRequested());
          return _refreshCompleter!.future;
        },
        child: widget.state.quotes.isEmpty
            ? LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: const NubiaEmptyState(
                      key: Key('financial_empty'),
                      icon: Icons.receipt_long_outlined,
                      title: 'Aucun devis en attente',
                      subtitle:
                          'Vos plans de soins à signer ou à régler apparaîtront ici.',
                    ),
                  ),
                ),
              )
            : ListView.separated(
                key: const Key('financial_list'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: widget.state.quotes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) =>
                    _QuoteTile(quote: widget.state.quotes[i]),
              ),
      ),
    );
  }
}

class _QuoteTile extends StatelessWidget {
  const _QuoteTile({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = _StatusStyle.of(quote.status);

    // L'API ne renvoie pas toujours de nom de praticien sur la liste : on titre
    // alors par la date du devis.
    final title = quote.practitionerName.isNotEmpty
        ? quote.practitionerName
        : 'Devis du ${_formatDate(quote.createdAt)}';

    return NubiaCard(
      key: Key('quote_item_${quote.id}'),
      state: NubiaCardState.interactive,
      onTap: () =>
          context.read<FinancialBloc>().add(FinancialQuoteSelected(quote.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: cs.onSurface),
                ),
              ),
              const SizedBox(width: 12),
              StatusPill(label: style.label, variant: style.variant),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reste à charge',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatCents(quote.patientShareCents),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: cs.onSurface,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatDate(quote.createdAt),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Détail d'un devis
// ---------------------------------------------------------------------------

class _QuoteDetailView extends StatefulWidget {
  const _QuoteDetailView({required this.state});

  final FinancialQuoteDetail state;

  @override
  State<_QuoteDetailView> createState() => _QuoteDetailViewState();
}

class _QuoteDetailViewState extends State<_QuoteDetailView> {
  late final String _payKey =
      '${widget.state.quote.id}-pay-${DateTime.now().microsecondsSinceEpoch}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final quote = widget.state.quote;
    final style = _StatusStyle.of(quote.status);
    final canSign = quote.canSign;
    final canPay = quote.status == QuoteStatus.signed && quote.depositCents > 0;

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
                  amount: _formatCents(quote.totalCents),
                  caption: quote.practitionerName.isNotEmpty
                      ? quote.practitionerName
                      : 'Devis du ${_formatDate(quote.createdAt)}',
                  remainingLabel: 'Reste à charge',
                  remainingAmount: _formatCents(quote.patientShareCents),
                  remainingCaption: 'après remboursements',
                ),
                const SizedBox(height: 20),
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
                child: Text(
                  item.label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatCents(item.totalCents),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w500,
                  fontFeatures: _tabular,
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
              _formatCents(quote.depositCents),
              style: theme.textTheme.titleLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
                fontFeatures: _tabular,
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

// ---------------------------------------------------------------------------
// Signature en cours
// ---------------------------------------------------------------------------

class _SignatureView extends StatelessWidget {
  const _SignatureView({required this.state});

  final FinancialSignatureInProgress state;

  @override
  Widget build(BuildContext context) {
    return NubiaEmptyState(
      key: const Key('financial_signature'),
      icon: Icons.draw_outlined,
      title: 'Signature en cours',
      subtitle: 'Ouvrez le lien sécurisé pour signer votre devis, '
          'puis confirmez ci-dessous.',
      action: NubiaButton(
        key: const Key('btn_confirm_signature'),
        label: 'Confirmer la signature',
        icon: Icons.check,
        size: NubiaButtonSize.lg,
        onPressed: () => context
            .read<FinancialBloc>()
            .add(const FinancialSignatureCompleted()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paiement en cours
// ---------------------------------------------------------------------------

class _PaymentLoadingView extends StatelessWidget {
  const _PaymentLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Paiement en cours…',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Merci de patienter, ne fermez pas cette page.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reçu / paiement réussi
// ---------------------------------------------------------------------------

class _PaymentSuccessView extends StatelessWidget {
  const _PaymentSuccessView({required this.state});

  final FinancialPaymentSuccess state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;
    final quote = state.quote;

    return SafeArea(
      key: const Key('financial_success'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pastille de confirmation avec check.
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: tokens.successBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded,
                    size: 48, color: tokens.successFg),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Paiement confirmé',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.headlineSmall?.copyWith(color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Votre acompte a bien été reçu. Un reçu vous a été envoyé.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            // Reçu récapitulatif.
            NubiaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReceiptRow(
                    label: 'Acompte réglé',
                    value: _formatCents(quote.depositCents),
                    strong: true,
                  ),
                  Divider(height: 20, color: tokens.borderSubtle),
                  _ReceiptRow(
                    label: 'Reste à charge total',
                    value: _formatCents(quote.patientShareCents),
                  ),
                  const SizedBox(height: 8),
                  _ReceiptRow(
                    label: 'Solde restant',
                    value: _formatCents(
                        quote.patientShareCents - quote.depositCents),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            NubiaButton(
              key: const Key('btn_back_after_success'),
              label: 'Retour à mes devis',
              size: NubiaButtonSize.lg,
              onPressed: () => context
                  .read<FinancialBloc>()
                  .add(const FinancialBackToList()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            label,
            style: (strong
                    ? theme.textTheme.titleSmall
                    : theme.textTheme.bodyMedium)
                ?.copyWith(color: strong ? cs.onSurface : cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: (strong
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyMedium)
              ?.copyWith(
            color: cs.onSurface,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
            fontFeatures: _tabular,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers partagés
// ---------------------------------------------------------------------------

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// Mapping statut domaine ([QuoteStatus]) → libellé FR + variant [StatusPill].
class _StatusStyle {
  const _StatusStyle(this.label, this.variant);

  final String label;
  final StatusPillVariant variant;

  static _StatusStyle of(QuoteStatus status) => switch (status) {
        QuoteStatus.draft =>
          const _StatusStyle('Brouillon', StatusPillVariant.info),
        QuoteStatus.sent =>
          const _StatusStyle('À signer', StatusPillVariant.warning),
        QuoteStatus.signed =>
          const _StatusStyle('Signé', StatusPillVariant.success),
        QuoteStatus.expired =>
          const _StatusStyle('Expiré', StatusPillVariant.error),
        QuoteStatus.cancelled =>
          const _StatusStyle('Annulé', StatusPillVariant.error),
      };
}

String _formatDate(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

/// Formate des centimes en euros avec séparateur de milliers (espace fine
/// insécable) et virgule décimale ; ex. `206000` → « 2 060 € », `8050` →
/// « 80,50 € ». Un montant négatif est préfixé par un « − » typographique.
String _formatCents(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = abs % 100;

  final wholeStr = _groupThousands(whole);
  final body =
      frac == 0 ? wholeStr : '$wholeStr,${frac.toString().padLeft(2, '0')}';
  return '${negative ? '−' : ''}$body €';
}

String _groupThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(' '); // espace fine insécable
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
