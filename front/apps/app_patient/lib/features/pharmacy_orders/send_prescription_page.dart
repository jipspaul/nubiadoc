import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../pharmacy/widgets/pharmacy_card.dart';
import 'send_prescription_cubit.dart';

/// Transmission d'une ordonnance à la pharmacie (commande click-and-collect).
class SendPrescriptionPage extends StatelessWidget {
  const SendPrescriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SendPrescriptionCubit>(
      create: (_) => GetIt.instance<SendPrescriptionCubit>()..load(),
      child: const SendPrescriptionBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class SendPrescriptionBody extends StatelessWidget {
  const SendPrescriptionBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer une ordonnance')),
      body: BlocBuilder<SendPrescriptionCubit, SendPrescriptionState>(
        builder: (context, state) {
          switch (state) {
            case SendPrescriptionLoading():
              return const Center(child: CircularProgressIndicator());
            case SendPrescriptionError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context.read<SendPrescriptionCubit>().load(),
              );
            case SendPrescriptionSuccess(:final order):
              return _SuccessView(order: order);
            case SendPrescriptionReady():
              return _ReadyView(state: state);
          }
        },
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.state});

  final SendPrescriptionReady state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<SendPrescriptionCubit>();
    final locale = MaterialLocalizations.of(context);

    if (state.prescriptions.isEmpty) {
      return const NubiaEmptyState(
        icon: Icons.medication_outlined,
        title: 'Aucune ordonnance à envoyer',
        subtitle: 'Vos ordonnances signées par votre praticien '
            'apparaîtront ici.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('1. Choisissez l\'ordonnance',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final prescription in state.prescriptions)
            ListRow(
              key: Key('prescription_${prescription.id}'),
              title:
                  'Ordonnance du ${locale.formatShortDate(prescription.createdAt.toLocal())}',
              subtitle: prescription.status == PrescriptionStatus.sent
                  ? 'Déjà transmise une fois'
                  : 'Signée',
              trailing: state.selectedPrescription?.id == prescription.id
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: () => cubit.selectPrescription(prescription),
            ),
          const SizedBox(height: 24),
          Text('2. Pharmacie destinataire', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (state.pharmacy != null)
            PharmacyCard(pharmacy: state.pharmacy!)
          else
            const NubiaCard(
              child: Text('Aucune pharmacie déclarée — choisissez-en une.'),
            ),
          const SizedBox(height: 8),
          NubiaButton(
            key: const Key('choose_other_pharmacy'),
            label: state.pharmacy == null
                ? 'Choisir une pharmacie'
                : 'Choisir une autre pharmacie',
            variant: NubiaButtonVariant.secondary,
            onPressed: () async {
              final pharmacy = await context
                  .push<Pharmacy>('/pharmacy/search?selection=true');
              if (pharmacy != null) {
                cubit.selectPharmacy(pharmacy);
              }
            },
          ),
          const SizedBox(height: 24),
          NubiaButton(
            key: const Key('send_prescription_submit'),
            label: 'Transmettre à la pharmacie',
            isLoading: state.submitting,
            onPressed: state.canSubmit ? cubit.submit : null,
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.order});

  final PharmacyOrder order;

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
            Text('Ordonnance transmise', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${order.pharmacyName ?? 'Votre pharmacie'} prépare votre '
              'commande. Vous serez notifié à chaque étape.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            NubiaButton(
              key: const Key('send_success_done'),
              label: 'Fermer',
              onPressed: () => context.go('/pharmacy'),
            ),
          ],
        ),
      ),
    );
  }
}
