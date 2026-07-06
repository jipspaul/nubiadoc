import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_bloc.dart';
import 'devis_event.dart';
import 'devis_state.dart';

/// Plan de traitement / devis — vue praticien.
///
/// Liste des devis du cabinet → détail (montant + reste à charge via
/// [AmountHeader], phases et lignes d'actes via [QuoteCard]) → envoi au patient
/// pour signature (CTA « Envoyer » sticky).
///
/// Doit être placé sous un [BlocProvider<DevisBloc>] (fourni par [DevisPage] ou
/// le parent).
class DevisPage extends StatelessWidget {
  const DevisPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          GetIt.instance<DevisBloc>()..add(const DevisListRequested()),
      child: const DevisBody(),
    );
  }
}

// ---------------------------------------------------------------------------

/// Corps de l'écran devis, consommable dans ProShell bodyBuilder.
class DevisBody extends StatelessWidget {
  const DevisBody({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DevisBloc, DevisState>(
      listenWhen: (previous, current) => current is DevisSendFailure,
      listener: (context, state) {
        if (state is DevisSendFailure) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                key: const Key('devis_send_error_snackbar'),
                content: Text(state.message.isEmpty
                    ? 'Envoi impossible.'
                    : state.message),
              ),
            );
        }
      },
      builder: (context, state) {
        if (state is DevisInitial || state is DevisLoading) {
          return const _LoadingView(key: Key('devis_loading'));
        }
        if (state is DevisError) {
          return NubiaErrorWidget(
            key: const Key('devis_error'),
            message: state.message,
            onRetry: () =>
                context.read<DevisBloc>().add(const DevisListRequested()),
          );
        }
        if (state is DevisListLoaded) {
          return _ListView(quotes: state.quotes);
        }
        if (state is DevisDetailLoaded) {
          return _DetailView(quote: state.quote);
        }
        if (state is DevisSendInProgress) {
          return _DetailView(quote: state.quote, sending: true);
        }
        // Échec d'envoi : on reste sur le détail pour permettre un nouvel essai.
        if (state is DevisSendFailure) {
          return _DetailView(quote: state.quote);
        }
        if (state is DevisSent) {
          return _SentView(quote: state.quote);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Chargement (skeleton)
// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: const [
        _DevisSkeletonCard(),
        SizedBox(height: 12),
        _DevisSkeletonCard(),
        SizedBox(height: 12),
        _DevisSkeletonCard(),
      ],
    );
  }
}

class _DevisSkeletonCard extends StatelessWidget {
  const _DevisSkeletonCard();

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
              NubiaSkeletonLoader(height: 20, width: 72),
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

class _ListView extends StatelessWidget {
  const _ListView({required this.quotes});

  final List<CabinetQuote> quotes;

  @override
  Widget build(BuildContext context) {
    if (quotes.isEmpty) {
      return NubiaEmptyState(
        key: const Key('devis_empty'),
        icon: Icons.receipt_long_outlined,
        title: 'Aucun devis',
        subtitle: 'Les plans de traitement du cabinet apparaîtront ici.',
        action: NubiaButton(
          key: const Key('devis_reload_button'),
          label: 'Actualiser',
          variant: NubiaButtonVariant.secondary,
          icon: Icons.refresh,
          onPressed: () =>
              context.read<DevisBloc>().add(const DevisListRequested()),
        ),
      );
    }

    return ListView.separated(
      key: const Key('devis_list'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: quotes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _QuoteTile(quote: quotes[i]),
    );
  }
}

class _QuoteTile extends StatelessWidget {
  const _QuoteTile({required this.quote});

  final CabinetQuote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = _StatusStyle.of(quote.status);

    final title = quote.patientName.isNotEmpty
        ? quote.patientName
        : 'Devis du ${_formatDate(quote.createdAt)}';

    return NubiaCard(
      key: Key('devis_item_${quote.id}'),
      state: NubiaCardState.interactive,
      onTap: () => context.read<DevisBloc>().add(DevisQuoteSelected(quote.id)),
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

class _DetailView extends StatelessWidget {
  const _DetailView({required this.quote, this.sending = false});

  final CabinetQuote quote;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final style = _StatusStyle.of(quote.status);
    final items = quote.items ?? const <QuoteLineItem>[];
    final bool canSend = quote.status == CabinetQuoteStatus.draft;

    return Column(
      key: const Key('devis_detail'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: StatusPill(label: style.label, variant: style.variant),
                ),
                const SizedBox(height: 16),
                AmountHeader(
                  label: 'Total du plan de traitement',
                  amount: _formatCents(quote.totalCents),
                  caption: quote.patientName.isNotEmpty
                      ? quote.patientName
                      : 'Devis du ${_formatDate(quote.createdAt)}',
                  remainingLabel: 'Reste à charge',
                  remainingAmount: _formatCents(quote.patientShareCents),
                  remainingCaption: 'après remboursements',
                ),
                const SizedBox(height: 20),
                // Phase de soins + lignes d'actes (QuoteCard).
                QuoteCard(
                  title: 'Plan de soins',
                  subtitle: 'Phase 1 · ${items.length} acte(s)',
                  status: _cardStatus(quote.status),
                  lines: [
                    for (final item in items)
                      QuoteLine(
                        label: _lineLabel(item),
                        amount: _formatCents(item.totalCents),
                      ),
                  ],
                  total: _formatCents(quote.totalCents),
                ),
                const SizedBox(height: 12),
                const _ReassuranceRow(),
              ],
            ),
          ),
        ),
        _StickyActions(
          children: [
            if (canSend)
              NubiaButton(
                key: const Key('btn_send_devis'),
                label: 'Envoyer au patient',
                icon: Icons.send_outlined,
                size: NubiaButtonSize.lg,
                isLoading: sending,
                onPressed: sending
                    ? null
                    : () => context
                        .read<DevisBloc>()
                        .add(DevisSendRequested(quote.id)),
              ),
            NubiaButton(
              key: const Key('btn_back_devis'),
              label: 'Retour à la liste',
              variant: NubiaButtonVariant.tertiary,
              size: NubiaButtonSize.lg,
              onPressed: sending
                  ? null
                  : () =>
                      context.read<DevisBloc>().add(const DevisBackToList()),
            ),
          ],
        ),
      ],
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
              const TextSpan(
                text: 'Envoyé pour signature électronique ',
                children: [
                  TextSpan(
                    text: '(eIDAS)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' · devis horodaté et archivé'),
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

// ---------------------------------------------------------------------------
// Devis envoyé (confirmation)
// ---------------------------------------------------------------------------

class _SentView extends StatelessWidget {
  const _SentView({required this.quote});

  final CabinetQuote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return SafeArea(
      key: const Key('devis_sent'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              'Devis envoyé',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.headlineSmall?.copyWith(color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              quote.patientName.isNotEmpty
                  ? 'Le devis a été transmis à ${quote.patientName} pour signature.'
                  : 'Le devis a été transmis au patient pour signature.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            NubiaButton(
              key: const Key('btn_back_after_send'),
              label: 'Retour aux devis',
              size: NubiaButtonSize.lg,
              onPressed: () =>
                  context.read<DevisBloc>().add(const DevisBackToList()),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barre d'actions sticky
// ---------------------------------------------------------------------------

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
// Helpers
// ---------------------------------------------------------------------------

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// Libellé d'une ligne d'acte : intitulé + métadonnées (dent / code CCAM).
String _lineLabel(QuoteLineItem item) {
  final meta = <String>[
    if (item.toothLabel != null && item.toothLabel!.isNotEmpty)
      'dent ${item.toothLabel}',
    if (item.ccamCode != null && item.ccamCode!.isNotEmpty) item.ccamCode!,
  ];
  return meta.isEmpty ? item.label : '${item.label} · ${meta.join(' · ')}';
}

/// Mapping statut cabinet → statut carte [QuoteCard].
QuoteCardStatus _cardStatus(CabinetQuoteStatus status) => switch (status) {
      CabinetQuoteStatus.draft => QuoteCardStatus.draft,
      CabinetQuoteStatus.sent => QuoteCardStatus.sent,
      CabinetQuoteStatus.signed => QuoteCardStatus.signed,
      CabinetQuoteStatus.expired => QuoteCardStatus.expired,
      CabinetQuoteStatus.cancelled => QuoteCardStatus.refused,
    };

/// Mapping statut cabinet → libellé FR + variant [StatusPill].
class _StatusStyle {
  const _StatusStyle(this.label, this.variant);

  final String label;
  final StatusPillVariant variant;

  static _StatusStyle of(CabinetQuoteStatus status) => switch (status) {
        CabinetQuoteStatus.draft =>
          const _StatusStyle('Brouillon', StatusPillVariant.info),
        CabinetQuoteStatus.sent =>
          const _StatusStyle('Envoyé', StatusPillVariant.warning),
        CabinetQuoteStatus.signed =>
          const _StatusStyle('Signé', StatusPillVariant.success),
        CabinetQuoteStatus.expired =>
          const _StatusStyle('Expiré', StatusPillVariant.error),
        CabinetQuoteStatus.cancelled =>
          const _StatusStyle('Annulé', StatusPillVariant.error),
      };
}

String _formatDate(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

/// Formate des centimes en euros : `206000` → « 2 060 € », `8050` → « 80,50 € ».
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
      buffer.write(' ');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
