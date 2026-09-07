import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'prescriptions_cubit.dart';

/// Liste des ordonnances du patient (#6232) — cible de la tuile « Mes
/// ordonnances » de l'accueil, `GET /v1/account/prescriptions`.
///
/// Crée son propre [BlocProvider] ; wrappée dans un `Scaffold` par le
/// routeur (voir `documents` pour le même agencement).
class PrescriptionsPage extends StatelessWidget {
  const PrescriptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<PrescriptionsCubit>()..load(),
      child: const PrescriptionsBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class PrescriptionsBody extends StatelessWidget {
  const PrescriptionsBody({super.key});

  String _statusLabel(PrescriptionStatus status) {
    switch (status) {
      case PrescriptionStatus.draft:
        return 'En attente de signature';
      case PrescriptionStatus.signed:
        return 'Signée';
      case PrescriptionStatus.sent:
        return 'Transmise à une pharmacie';
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PrescriptionsCubit, PrescriptionsState>(
      listenWhen: (previous, current) =>
          current is PrescriptionsDocumentReady ||
          current is PrescriptionsDocumentError,
      listener: (context, state) {
        if (state is PrescriptionsDocumentReady) {
          openDocumentUrl(state.url).then((opened) {
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Impossible d\'ouvrir cette ordonnance.'),
                ),
              );
            }
          });
        }
        if (state is PrescriptionsDocumentError) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      child: BlocBuilder<PrescriptionsCubit, PrescriptionsState>(
        builder: (context, state) {
          if (state is PrescriptionsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is PrescriptionsError) {
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () => context.read<PrescriptionsCubit>().load(),
            );
          }
          final prescriptions = switch (state) {
            PrescriptionsLoaded(:final prescriptions) => prescriptions,
            _ => const <PatientPrescription>[],
          };
          if (prescriptions.isEmpty) {
            return const NubiaEmptyState(
              key: Key('prescriptions_empty'),
              icon: Icons.medication_outlined,
              title: 'Aucune ordonnance',
              subtitle: 'Vos ordonnances signées par votre praticien '
                  'apparaîtront ici.',
            );
          }
          final locale = MaterialLocalizations.of(context);
          return ListView.separated(
            key: const Key('prescriptions_list'),
            padding: const EdgeInsets.all(16),
            itemCount: prescriptions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final prescription = prescriptions[index];
              return ListRow(
                key: Key('prescription_${prescription.id}'),
                title:
                    'Ordonnance du ${locale.formatShortDate(prescription.createdAt.toLocal())}',
                subtitle: _statusLabel(prescription.status),
                showDivider: false,
                trailing: prescription.documentId != null
                    ? const Icon(Icons.chevron_right)
                    : null,
                onTap: prescription.documentId != null
                    ? () => context
                        .read<PrescriptionsCubit>()
                        .openDocument(prescription.documentId!)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
