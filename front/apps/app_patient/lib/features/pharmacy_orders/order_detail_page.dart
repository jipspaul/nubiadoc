import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'orders_bloc.dart';
import 'widgets/order_billing_summary_card.dart';
import 'widgets/order_timeline.dart';
import 'widgets/pickup_qr_card.dart';

/// Détail d'une commande : timeline temps réel + QR de retrait quand prête.
class PatientOrderDetailPage extends StatelessWidget {
  const PatientOrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PatientOrderDetailCubit>(
      create: (_) => GetIt.instance<PatientOrderDetailCubit>()..load(orderId),
      child: const PatientOrderDetailBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class PatientOrderDetailBody extends StatelessWidget {
  const PatientOrderDetailBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi de commande')),
      body: BlocBuilder<PatientOrderDetailCubit, PatientOrderDetailState>(
        builder: (context, state) {
          switch (state) {
            case PatientOrderDetailLoading():
              return const Center(child: CircularProgressIndicator());
            case PatientOrderDetailError(:final message):
              return NubiaErrorWidget(message: message);
            case PatientOrderDetailLoaded(
                :final order,
                :final pickupToken,
                :final cancelling
              ):
              final theme = Theme.of(context);
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      order.pharmacyName ?? 'Votre pharmacie',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    OrderTimeline(order: order),
                    if (order.canShowPickupCode && pickupToken != null) ...[
                      const SizedBox(height: 16),
                      PickupQrCard(token: pickupToken),
                    ],
                    if (order.hasBillingSummary) ...[
                      const SizedBox(height: 16),
                      OrderBillingSummaryCard(order: order),
                    ],
                    if (order.status == PharmacyOrderStatus.received ||
                        order.status == PharmacyOrderStatus.preparing) ...[
                      const SizedBox(height: 24),
                      NubiaButton(
                        key: const Key('cancel_order_button'),
                        label: 'Annuler la commande',
                        variant: NubiaButtonVariant.secondary,
                        isLoading: cancelling,
                        onPressed: cancelling
                            ? null
                            : () => context
                                .read<PatientOrderDetailCubit>()
                                .cancelOrder(),
                      ),
                    ],
                  ],
                ),
              );
          }
        },
      ),
    );
  }
}
