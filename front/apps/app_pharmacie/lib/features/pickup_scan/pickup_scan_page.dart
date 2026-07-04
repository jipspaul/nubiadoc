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
      child: PickupScanBody(orderId: orderId),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class PickupScanBody extends StatelessWidget {
  const PickupScanBody({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner le retrait'),
        leading: BackButton(onPressed: () => context.go('/orders/$orderId')),
      ),
      body: BlocBuilder<PickupScanCubit, PickupScanState>(
        builder: (context, state) {
          if (state is PickupScanSuccess) {
            return _SuccessView(state: state);
          }
          final submitting = state is PickupScanSubmitting;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (QrScannerView.isSupported)
                  QrScannerView(
                    onCode: (code) =>
                        context.read<PickupScanCubit>().submit(code),
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
                  _InlineError(
                    key: const Key('pickup_invalid_code'),
                    message: state.message,
                  ),
                  const SizedBox(height: 8),
                ],
                if (state is PickupScanError) ...[
                  _InlineError(message: state.message),
                  const SizedBox(height: 8),
                ],
                ManualCodeField(
                  enabled: !submitting,
                  onSubmit: (code) =>
                      context.read<PickupScanCubit>().submit(code),
                ),
                if (submitting) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          );
        },
      ),
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

class _InlineError extends StatelessWidget {
  const _InlineError({super.key, required this.message});

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
