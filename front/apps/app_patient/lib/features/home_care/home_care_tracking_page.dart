import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'home_care_models.dart';
import 'home_care_tracking_cubit.dart';

/// Suivi d'une demande de visite : statut courant + annulation tant que
/// possible (`requested`/`offered`/`accepted`/`en_route`/`arrived`).
class HomeCareTrackingPage extends StatelessWidget {
  const HomeCareTrackingPage({super.key, required this.visitId});

  final String visitId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<HomeCareTrackingCubit>(
      create: (_) => GetIt.instance<HomeCareTrackingCubit>()..load(visitId),
      child: const HomeCareTrackingBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class HomeCareTrackingBody extends StatelessWidget {
  const HomeCareTrackingBody({super.key});

  static const _statusVariants = {
    'requested': StatusPillVariant.info,
    'offered': StatusPillVariant.info,
    'accepted': StatusPillVariant.progress,
    'en_route': StatusPillVariant.progress,
    'arrived': StatusPillVariant.progress,
    'done': StatusPillVariant.success,
    'cancelled': StatusPillVariant.error,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi de la visite')),
      body: BlocBuilder<HomeCareTrackingCubit, HomeCareTrackingState>(
        builder: (context, state) {
          switch (state) {
            case HomeCareTrackingLoading():
              return const Center(child: CircularProgressIndicator());
            case HomeCareTrackingError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context.read<HomeCareTrackingCubit>().refresh(),
              );
            case HomeCareTrackingLoaded(:final visit, :final cancelling):
              return RefreshIndicator(
                onRefresh: () => context.read<HomeCareTrackingCubit>().refresh(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    StatusPill(
                      key: const Key('home_care_status_pill'),
                      label: visitStatusLabels[visit.status] ?? visit.status,
                      variant:
                          _statusVariants[visit.status] ?? StatusPillVariant.neutral,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      visit.requestedActs
                          .map((a) => homeCareActs[a] ?? a)
                          .join(' · '),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(visit.addressLine),
                    const SizedBox(height: 8),
                    Text(NubiaMoney.formatCents(visit.estimatedPriceCents)),
                    const SizedBox(height: 24),
                    if (cancellableVisitStatuses.contains(visit.status))
                      NubiaButton(
                        key: const Key('home_care_cancel_button'),
                        label: 'Annuler la demande',
                        variant: NubiaButtonVariant.destructive,
                        isLoading: cancelling,
                        onPressed: cancelling
                            ? null
                            : () => context.read<HomeCareTrackingCubit>().cancel(),
                      ),
                  ],
                ),
              );
          }
        },
      ),
    );
  }
}
