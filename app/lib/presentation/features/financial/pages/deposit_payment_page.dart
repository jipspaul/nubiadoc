import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_bloc.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_event.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_state.dart';
import 'package:nubia_patient/presentation/features/financial/pages/payment_success_page.dart';
import 'package:nubia_patient/presentation/widgets/nubia_button.dart';

/// Page de paiement de l'acompte.
///
/// Propose Apple Pay / Google Pay (bouton natif simulé) et un fallback CB
/// (Stripe PaymentSheet). L'idempotency-key est générée et fixée dès la
/// première entrée sur la page — un retry conserve la même clé.
///
/// Cas limites :
/// - Acompte = 0 → [WedgeBloc] redirige automatiquement vers [PaymentSuccessPage].
/// - Paiement échoué → bouton « Réessayer » dispatche [WedgeDepositRetryRequested].
/// - Devis expiré → géré en amont dans [QuoteDetailPage].
class DepositPaymentPage extends StatefulWidget {
  const DepositPaymentPage({super.key, required this.quoteId});

  final String quoteId;

  @override
  State<DepositPaymentPage> createState() => _DepositPaymentPageState();
}

class _DepositPaymentPageState extends State<DepositPaymentPage> {
  // L'idempotency-key est fixée à la création de l'écran pour tout le cycle
  // de vie (y compris les retries).
  late final String _depositKey =
      '${widget.quoteId}-dep-${DateTime.now().microsecondsSinceEpoch}';

  void _pay() {
    context
        .read<WedgeBloc>()
        .add(WedgeDepositRequested(idempotencyKey: _depositKey));
  }

  void _retry() {
    context.read<WedgeBloc>().add(const WedgeDepositRetryRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WedgeBloc, WedgeState>(
      listenWhen: (_, next) => next is WedgePaymentSuccess,
      listener: (context, state) {
        if (state is WedgePaymentSuccess) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => PaymentSuccessPage(quote: state.quote),
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is WedgeSignatureDone) {
          final quote = state.quote;
          return Scaffold(
            appBar: AppBar(title: const Text('Paiement de l\'acompte')),
            body: _PaymentBody(
              depositCents: quote.depositCents,
              totalCents: quote.patientShareCents,
              isLoading: false,
              hasError: false,
              errorMessage: null,
              onPay: _pay,
              onRetry: null,
            ),
          );
        }

        if (state is WedgePaymentInProgress) {
          return Scaffold(
            appBar: AppBar(title: const Text('Paiement de l\'acompte')),
            body: _PaymentBody(
              depositCents: state.quote.depositCents,
              totalCents: state.quote.patientShareCents,
              isLoading: true,
              hasError: false,
              errorMessage: null,
              onPay: null,
              onRetry: null,
            ),
          );
        }

        if (state is WedgeError) {
          final quote = state.quote;
          if (quote != null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Paiement de l\'acompte')),
              body: _PaymentBody(
                depositCents: quote.depositCents,
                totalCents: quote.patientShareCents,
                isLoading: false,
                hasError: true,
                errorMessage: state.message,
                onPay: null,
                onRetry: _retry,
              ),
            );
          }
        }

        // Fallback : chargement
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _PaymentBody extends StatelessWidget {
  const _PaymentBody({
    required this.depositCents,
    required this.totalCents,
    required this.isLoading,
    required this.hasError,
    required this.errorMessage,
    required this.onPay,
    required this.onRetry,
  });

  final int depositCents;
  final int totalCents;
  final bool isLoading;
  final bool hasError;
  final String? errorMessage;
  final VoidCallback? onPay;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PaymentSummaryCard(
            depositCents: depositCents,
            totalCents: totalCents,
          ),
          const SizedBox(height: 24),
          if (hasError && errorMessage != null) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Spacer(),
          if (hasError)
            NubiaButton(
              key: const Key('btn_retry_payment'),
              label: 'Réessayer',
              size: NubiaButtonSize.lg,
              onPressed: onRetry,
            )
          else ...[
            // Apple Pay / Google Pay — bouton natif simulé en attendant
            // l'intégration du package `pay` (non encore dans pubspec.yaml).
            _NativePayButton(
              key: const Key('btn_native_pay'),
              isLoading: isLoading,
              onTap: onPay,
            ),
            const SizedBox(height: 12),
            NubiaButton(
              key: const Key('btn_card_pay'),
              label: 'Payer par carte',
              variant: NubiaButtonVariant.secondary,
              size: NubiaButtonSize.lg,
              isLoading: isLoading,
              onPressed: isLoading ? null : onPay,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Paiement sécurisé via Stripe',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PaymentSummaryCard extends StatelessWidget {
  const _PaymentSummaryCard({
    required this.depositCents,
    required this.totalCents,
  });

  final int depositCents;
  final int totalCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Récapitulatif', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Reste à charge total',
                    style: theme.textTheme.bodyMedium),
                Text(
                  '${(totalCents / 100).toStringAsFixed(2)} €',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Acompte à régler',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${(depositCents / 100).toStringAsFixed(2)} €',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NativePayButton extends StatelessWidget {
  const _NativePayButton({
    super.key,
    required this.isLoading,
    required this.onTap,
  });

  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 52,
      child: Material(
        color: isDark ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isLoading ? null : onTap,
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark ? Colors.black : Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.payment_rounded,
                        color: isDark ? Colors.black : Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Apple Pay / Google Pay',
                        style: TextStyle(
                          color: isDark ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
