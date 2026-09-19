import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'correspondent_stats_cubit.dart';

/// Fiche d'un correspondant (#7193) : coordonnées + stats d'adressage
/// (patients adressés, CA facturé, courriers envoyés).
class CorrespondentDetailDialog extends StatelessWidget {
  const CorrespondentDetailDialog({super.key, required this.correspondent});

  final CabinetCorrespondent correspondent;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<CorrespondentStatsCubit>()
        ..load(correspondent.id),
      child: AlertDialog(
        title: Text(correspondent.displayName),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (correspondent.specialty != null)
                  _InfoLine(
                    icon: Icons.medical_information_outlined,
                    label: 'Spécialité',
                    value: correspondent.specialty!,
                  ),
                if (correspondent.email != null)
                  _InfoLine(
                    icon: Icons.mail_outline,
                    label: 'E-mail',
                    value: correspondent.email!,
                  ),
                if (correspondent.phone != null)
                  _InfoLine(
                    icon: Icons.phone_outlined,
                    label: 'Téléphone',
                    value: correspondent.phone!,
                  ),
                if (correspondent.address != null)
                  _InfoLine(
                    icon: Icons.location_on_outlined,
                    label: 'Adresse',
                    value: correspondent.address!,
                  ),
                if (correspondent.rpps != null)
                  _InfoLine(
                    icon: Icons.badge_outlined,
                    label: 'RPPS',
                    value: correspondent.rpps!,
                  ),
                if (correspondent.notes != null)
                  _InfoLine(
                    icon: Icons.notes_outlined,
                    label: 'Notes',
                    value: correspondent.notes!,
                  ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const _CorrespondentStats(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('correspondent_detail_close'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 3),
          ),
        ],
      ),
    );
  }
}

class _CorrespondentStats extends StatelessWidget {
  const _CorrespondentStats();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CorrespondentStatsCubit, CorrespondentStatsState>(
      builder: (context, state) => switch (state) {
        CorrespondentStatsLoading() => const Center(
            key: Key('correspondent_stats_loading'),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(),
            ),
          ),
        CorrespondentStatsError(:final message) => Text(
            message,
            key: const Key('correspondent_stats_error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        CorrespondentStatsLoaded(:final stats) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patients adressés : ${stats.referredPatientsCount}',
                key: const Key('correspondent_stats_referred_patients'),
              ),
              const SizedBox(height: 6),
              Text(
                'CA facturé : '
                '${NubiaMoney.formatCents(stats.billedRevenueCents)}',
                key: const Key('correspondent_stats_billed_revenue'),
              ),
              const SizedBox(height: 6),
              Text(
                'Courriers envoyés : ${stats.lettersSentCount}',
                key: const Key('correspondent_stats_letters_sent'),
              ),
            ],
          ),
      },
    );
  }
}
