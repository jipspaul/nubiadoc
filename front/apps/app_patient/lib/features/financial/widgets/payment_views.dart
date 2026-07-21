import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../financial_bloc.dart';
import '../financial_event.dart';
import '../financial_state.dart';
import 'financial_format_utils.dart';

/// États paiement acompte (en cours / reçu) — extrait de
/// `financial_page.dart` (#4061, CLAUDE.md plafond 700 lignes).

class PaymentLoadingView extends StatelessWidget {
  const PaymentLoadingView({super.key});

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

class PaymentSuccessView extends StatelessWidget {
  const PaymentSuccessView({super.key, required this.state});

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
                    value: formatQuoteCents(quote.depositCents),
                    strong: true,
                  ),
                  Divider(height: 20, color: tokens.borderSubtle),
                  _ReceiptRow(
                    label: 'Reste à charge total',
                    value: formatQuoteCents(quote.patientShareCents),
                  ),
                  const SizedBox(height: 8),
                  _ReceiptRow(
                    label: 'Solde restant',
                    value: formatQuoteCents(
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
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}
