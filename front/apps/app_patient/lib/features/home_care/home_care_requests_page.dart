import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/app_router.dart';
import 'home_care_list_cubit.dart';
import 'home_care_models.dart';

/// Historique des demandes de visite infirmière à domicile — point d'entrée
/// vers une nouvelle demande (`POST /v1/account/visit-requests`) et vers le
/// suivi d'une demande en cours.
class HomeCareRequestsPage extends StatelessWidget {
  const HomeCareRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<HomeCareListCubit>(
      create: (_) => GetIt.instance<HomeCareListCubit>()..load(),
      child: const HomeCareRequestsBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class HomeCareRequestsBody extends StatelessWidget {
  const HomeCareRequestsBody({super.key});

  static const _statusVariants = {
    'requested': StatusPillVariant.info,
    'offered': StatusPillVariant.info,
    'accepted': StatusPillVariant.progress,
    'en_route': StatusPillVariant.progress,
    'arrived': StatusPillVariant.progress,
    'done': StatusPillVariant.success,
    'cancelled': StatusPillVariant.error,
    'expired': StatusPillVariant.error,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Soins à domicile')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('home_care_new_fab'),
        onPressed: () => context.push(AppRouter.homeCareNew),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle demande'),
      ),
      body: BlocBuilder<HomeCareListCubit, HomeCareListState>(
        builder: (context, state) {
          switch (state) {
            case HomeCareListLoading():
              return const Center(child: CircularProgressIndicator());
            case HomeCareListError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context.read<HomeCareListCubit>().load(),
              );
            case HomeCareListLoaded(:final requests):
              if (requests.isEmpty) {
                return const NubiaEmptyState(
                  icon: Icons.medical_services_outlined,
                  title: 'Aucune demande',
                  subtitle: 'Demandez la visite d\'une infirmière à domicile '
                      'pour un soin (pansement, prise de sang…).',
                );
              }
              return ListView.builder(
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  final visit = requests[index];
                  return ListRow(
                    key: Key('home_care_request_${visit.id}'),
                    title: visit.requestedActs
                        .map((a) => homeCareActs[a] ?? a)
                        .join(' · '),
                    subtitle: '${visit.addressLine} · '
                        '${NubiaMoney.formatCents(visit.estimatedPriceCents)}',
                    trailing: StatusPill(
                      label: visitStatusLabels[visit.status] ?? visit.status,
                      variant:
                          _statusVariants[visit.status] ?? StatusPillVariant.neutral,
                    ),
                    onTap: () =>
                        context.push('${AppRouter.homeCare}/${visit.id}'),
                  );
                },
              );
          }
        },
      ),
    );
  }
}
