import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../send_to_pharmacy_cubit.dart';
import 'pharmacy_picker_sheet.dart';

/// Carte « Envoyer à la pharmacie » de la confirmation de signature :
/// pharmacie déclarée du patient présélectionnée, modifiable, envoi en un tap.
class SendToPharmacyCard extends StatelessWidget {
  const SendToPharmacyCard({super.key, required this.prescription});

  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<SendToPharmacyCubit, SendToPharmacyState>(
      builder: (context, state) {
        switch (state) {
          case SendToPharmacyLoading():
            return const NubiaCard(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          case SendToPharmacySent(:final pharmacy):
            return NubiaCard(
              key: const Key('send_to_pharmacy_done'),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Ordonnance transmise à ${pharmacy.name}. '
                      'Le patient suivra sa commande depuis son application.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            );
          case SendToPharmacyError(:final message):
            return NubiaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(message,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.error)),
                  const SizedBox(height: 8),
                  NubiaButton(
                    key: const Key('send_to_pharmacy_retry'),
                    label: 'Réessayer',
                    variant: NubiaButtonVariant.secondary,
                    onPressed: () => context
                        .read<SendToPharmacyCubit>()
                        .load(prescription.patientId),
                  ),
                ],
              ),
            );
          case SendToPharmacyReady(:final pharmacy, :final sending):
            return NubiaCard(
              key: const Key('send_to_pharmacy_card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Envoyer à la pharmacie',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (pharmacy != null)
                    Text(
                      '${pharmacy.name}'
                      '${pharmacy.address != null ? ' — ${pharmacy.address}' : ''}',
                      key: const Key('send_to_pharmacy_target'),
                      style: theme.textTheme.bodyMedium,
                    )
                  else
                    Text(
                      'Le patient n\'a pas déclaré de pharmacie — '
                      'choisissez-en une.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 12),
                  NubiaButton(
                    key: const Key('send_to_pharmacy_button'),
                    label: 'Envoyer à la pharmacie',
                    isLoading: sending,
                    onPressed: pharmacy != null && !sending
                        ? () => context
                            .read<SendToPharmacyCubit>()
                            .send(prescription.id)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  NubiaButton(
                    key: const Key('choose_pharmacy_button'),
                    label: 'Choisir une autre pharmacie',
                    variant: NubiaButtonVariant.secondary,
                    onPressed: sending
                        ? null
                        : () async {
                            final cubit = context.read<SendToPharmacyCubit>();
                            final selected =
                                await showPharmacyPickerSheet(context);
                            if (selected != null) {
                              cubit.selectPharmacy(selected);
                            }
                          },
                  ),
                ],
              ),
            );
        }
      },
    );
  }
}
