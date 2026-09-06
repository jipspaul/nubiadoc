import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/back_or_home_leading.dart';
import 'my_pharmacy_cubit.dart';
import 'widgets/pharmacy_card.dart';

/// « Ma pharmacie » : pharmacie déclarée du patient + envoi d'ordonnance.
class MyPharmacyPage extends StatelessWidget {
  const MyPharmacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MyPharmacyCubit>(
      create: (_) => GetIt.instance<MyPharmacyCubit>()..load(),
      child: const MyPharmacyBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class MyPharmacyBody extends StatelessWidget {
  const MyPharmacyBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // #6236 : accessible via `context.go` (URL bookmarkable) autant que via
      // le tab bar — `canPop()` y est donc systématiquement faux, comme pour
      // un deep-link direct (même pattern que `financial`/`oubliettes`/
      // `reviews` dans `app_router.dart`).
      appBar: AppBar(
        leading: backOrHomeLeading(context),
        title: const Text('Ma pharmacie'),
      ),
      body: BlocBuilder<MyPharmacyCubit, MyPharmacyState>(
        builder: (context, state) {
          switch (state) {
            case MyPharmacyLoading():
              return const Center(child: CircularProgressIndicator());
            case MyPharmacyError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context.read<MyPharmacyCubit>().load(),
              );
            case MyPharmacyLoaded(:final pharmacy):
              if (pharmacy == null) {
                return NubiaEmptyState(
                  icon: Icons.local_pharmacy_outlined,
                  title: 'Aucune pharmacie déclarée',
                  subtitle: 'Déclarez votre pharmacie pour lui transmettre '
                      'vos ordonnances en un geste.',
                  action: NubiaButton(
                    key: const Key('declare_pharmacy_button'),
                    label: 'Déclarer ma pharmacie',
                    onPressed: () => _pickAndDeclare(context),
                  ),
                );
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PharmacyCard(pharmacy: pharmacy),
                    const SizedBox(height: 16),
                    NubiaButton(
                      key: const Key('send_prescription_button'),
                      label: 'Envoyer une ordonnance',
                      onPressed: () => context.push('/pharmacy/send'),
                    ),
                    const SizedBox(height: 8),
                    NubiaButton(
                      key: const Key('my_orders_button'),
                      label: 'Suivre mes commandes',
                      variant: NubiaButtonVariant.secondary,
                      onPressed: () => context.push('/pharmacy/orders'),
                    ),
                    const SizedBox(height: 8),
                    NubiaButton(
                      key: const Key('my_pharmacy_quotes_button'),
                      label: 'Mes devis pharmacie',
                      variant: NubiaButtonVariant.secondary,
                      onPressed: () => context.push('/pharmacy/quotes'),
                    ),
                    const SizedBox(height: 8),
                    NubiaButton(
                      key: const Key('change_pharmacy_button'),
                      label: 'Changer de pharmacie',
                      variant: NubiaButtonVariant.secondary,
                      onPressed: () => _pickAndDeclare(context),
                    ),
                  ],
                ),
              );
          }
        },
      ),
    );
  }

  Future<void> _pickAndDeclare(BuildContext context) async {
    final cubit = context.read<MyPharmacyCubit>();
    final pharmacy = await context.push<Pharmacy>('/pharmacy/search');
    if (pharmacy != null) {
      await cubit.declare(pharmacy.id);
    }
  }
}
