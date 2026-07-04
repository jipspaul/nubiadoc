import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'orders_bloc.dart';

/// Suivi des commandes click-and-collect du patient.
class PatientOrdersPage extends StatelessWidget {
  const PatientOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PatientOrdersBloc>(
      create: (_) => GetIt.instance<PatientOrdersBloc>()
        ..add(const PatientOrdersRequested()),
      child: const PatientOrdersBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class PatientOrdersBody extends StatelessWidget {
  const PatientOrdersBody({super.key});

  static const _statusLabels = {
    PharmacyOrderStatus.received: 'Reçue',
    PharmacyOrderStatus.preparing: 'En préparation',
    PharmacyOrderStatus.ready: 'Prête',
    PharmacyOrderStatus.pickedUp: 'Retirée',
    PharmacyOrderStatus.rejected: 'Refusée',
    PharmacyOrderStatus.cancelled: 'Annulée',
  };

  static const _statusVariants = {
    PharmacyOrderStatus.received: StatusPillVariant.info,
    PharmacyOrderStatus.preparing: StatusPillVariant.warning,
    PharmacyOrderStatus.ready: StatusPillVariant.success,
    PharmacyOrderStatus.pickedUp: StatusPillVariant.info,
    PharmacyOrderStatus.rejected: StatusPillVariant.error,
    PharmacyOrderStatus.cancelled: StatusPillVariant.error,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes commandes')),
      body: BlocBuilder<PatientOrdersBloc, PatientOrdersState>(
        builder: (context, state) {
          switch (state) {
            case PatientOrdersLoading():
              return const Center(child: CircularProgressIndicator());
            case PatientOrdersError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context
                    .read<PatientOrdersBloc>()
                    .add(const PatientOrdersRequested()),
              );
            case PatientOrdersLoaded(:final orders):
              if (orders.isEmpty) {
                return const NubiaEmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Aucune commande',
                  subtitle: 'Transmettez une ordonnance à votre pharmacie '
                      'pour suivre sa préparation ici.',
                );
              }
              return ListView.builder(
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final date = MaterialLocalizations.of(context)
                      .formatShortDate(order.createdAt.toLocal());
                  return ListRow(
                    key: Key('patient_order_${order.id}'),
                    title: order.pharmacyName ?? 'Pharmacie',
                    subtitle: 'Envoyée le $date',
                    trailing: StatusPill(
                      label: _statusLabels[order.status]!,
                      variant: _statusVariants[order.status]!,
                    ),
                    onTap: () => context.push('/pharmacy/orders/${order.id}'),
                  );
                },
              );
          }
        },
      ),
    );
  }
}
