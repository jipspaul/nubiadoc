import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../orders/widgets/order_status_pill.dart';
import 'pickup_scan_cubit.dart';
import 'widgets/manual_code_field.dart';
import 'widgets/qr_scanner_view.dart';

/// Scan du QR de retrait du patient (ready → retirée).
///
/// La caméra n'est montée que sur les plateformes supportées ; la saisie
/// manuelle du code est TOUJOURS proposée (fallback Windows/Linux, caméra
/// refusée, QR illisible).
class PickupScanPage extends StatelessWidget {
  const PickupScanPage({super.key, required this.orderId});

  /// Commande d'origine (pour le retour) — le scan lui-même est PAR TOKEN.
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PickupScanCubit>(
      create: (_) => GetIt.instance<PickupScanCubit>(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scanner le retrait'),
          leading:
              BackButton(onPressed: () => context.go('/orders/$orderId')),
        ),
        body: PickupScanBody(orderId: orderId),
      ),
    );
  }
}

/// Corps du scan — public pour les tests widget et pour être monté comme
/// panneau du volet droit (voir [OrderDetailBody]) en plus de son usage en
/// page complète via [PickupScanPage] (accès direct par route).
class PickupScanBody extends StatelessWidget {
  const PickupScanBody({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PickupScanCubit, PickupScanState>(
      builder: (context, state) {
        if (state is PickupScanSuccess) {
          return _SuccessView(state: state);
        }
        if (state is PickupScanMismatch) {
          return _MismatchView(state: state);
        }
        final submitting = state is PickupScanSubmitting;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (QrScannerView.isSupported)
                QrScannerView(
                  onCode: (code) => context
                      .read<PickupScanCubit>()
                      .submit(code, expectedOrderId: orderId),
                )
              else
                const NubiaCard(
                  child: Text(
                    'Le scan caméra n\'est pas disponible sur cette '
                    'plateforme — saisissez le code ci-dessous.',
                  ),
                ),
              const SizedBox(height: 16),
              if (state is PickupScanInvalidCode) ...[
                _InvalidCodeError(
                  key: const Key('pickup_invalid_code'),
                  cause: state.cause,
                  message: state.message,
                ),
                const SizedBox(height: 8),
                NubiaButton(
                  key: const Key('pickup_error_retry'),
                  label: 'Réessayer',
                  icon: Icons.qr_code_scanner,
                  variant: NubiaButtonVariant.destructive,
                  onPressed: () => context.read<PickupScanCubit>().reset(),
                ),
                const SizedBox(height: 8),
              ],
              if (state is PickupScanError) ...[
                _InlineError(message: state.message),
                const SizedBox(height: 8),
                NubiaButton(
                  key: const Key('pickup_error_retry'),
                  label: 'Réessayer',
                  icon: Icons.qr_code_scanner,
                  variant: NubiaButtonVariant.destructive,
                  onPressed: () => context.read<PickupScanCubit>().reset(),
                ),
                const SizedBox(height: 8),
              ],
              ManualCodeField(
                enabled: !submitting,
                onSubmit: (code) => context
                    .read<PickupScanCubit>()
                    .submit(code, expectedOrderId: orderId),
              ),
              if (submitting) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.state});

  final PickupScanSuccess state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Commande retirée', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              state.order.patientDisplayName ?? 'Patient',
              key: const Key('pickup_success_patient'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            OrderStatusPill(status: state.order.status),
            const SizedBox(height: 24),
            NubiaButton(
              key: const Key('pickup_back_to_orders'),
              label: 'Retour aux commandes',
              onPressed: () => context.go('/'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Garde-fou bloquant : le QR scanné est valide mais concerne une autre
/// commande que celle en main du pharmacien — la délivrance est interdite.
class _MismatchView extends StatelessWidget {
  const _MismatchView({required this.state});

  final PickupScanMismatch state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('pickup_mismatch_card'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.dangerBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NubiaColors.dangerBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error, color: tokens.dangerFg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ce QR ne correspond pas à cette commande',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: tokens.dangerFg),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Le code scanné est valide, mais il concerne un autre '
                  'patient. Ne délivrez pas ce sachet.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: tokens.dangerFg),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _MismatchColumn(
                        label: 'Sachet en main',
                        value: 'Commande ${state.expectedOrderId}',
                        color: tokens.dangerFg,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _MismatchColumn(
                        label: 'QR scanné',
                        value: '${state.scannedOrder.patientDisplayName ?? 'Patient inconnu'} — ${state.scannedOrder.id}',
                        color: tokens.dangerFg,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: NubiaButton(
                        key: const Key('pickup_mismatch_retry'),
                        label: 'Réessayer',
                        icon: Icons.qr_code_scanner,
                        variant: NubiaButtonVariant.destructive,
                        onPressed: () =>
                            context.read<PickupScanCubit>().reset(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NubiaButton(
                        key: const Key('pickup_mismatch_open_order'),
                        label: 'Ouvrir ${state.scannedOrder.id}',
                        variant: NubiaButtonVariant.secondary,
                        onPressed: () => context
                            .go('/orders/${state.scannedOrder.id}'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const NubiaButton(
            label: 'Valider le retrait',
            onPressed: null,
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Scannez le bon QR pour débloquer la validation',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _MismatchColumn extends StatelessWidget {
  const _MismatchColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Une conduite distincte par cause (#4884) : code inconnu (404), commande
/// pas au bon statut (409) ou code expiré (410) n'appellent pas la même
/// action du pharmacien.
class _InvalidCodeError extends StatelessWidget {
  const _InvalidCodeError({
    super.key,
    required this.cause,
    required this.message,
  });

  final PickupScanInvalidCause cause;
  final String message;

  String get _title {
    switch (cause) {
      case PickupScanInvalidCause.unknownCode:
        return 'Code inconnu';
      case PickupScanInvalidCause.wrongStatus:
        return 'Commande pas au bon statut';
      case PickupScanInvalidCause.expired:
        return 'Code expiré';
    }
  }

  String get _guidance {
    switch (cause) {
      case PickupScanInvalidCause.unknownCode:
        return 'Revérifiez le code sur l\'ordonnance et réessayez.';
      case PickupScanInvalidCause.wrongStatus:
        return 'Cette commande n\'est pas au bon état pour être retirée.';
      case PickupScanInvalidCause.expired:
        return 'Ce code a expiré — régénérez-le puis rescannez.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.dangerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NubiaColors.dangerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: tokens.dangerFg, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: tokens.dangerFg, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _guidance,
            style: theme.textTheme.bodyMedium?.copyWith(color: tokens.dangerFg),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: tokens.dangerFg.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      message,
      style:
          theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
    );
  }
}
