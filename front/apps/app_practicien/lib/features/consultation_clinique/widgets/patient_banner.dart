import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'session_timer.dart';

/// Bandeau patient pleine largeur de la vue fauteuil (maquette
/// `bo-praticien-core.jsx` : avatar, nom, « 48 ans · RDV 09:00 · motif —
/// phase 2/3 », badges d'alerte, statut de séance, timer).
///
/// Les alertes médicales sont en AFFICHAGE PASSIF uniquement (périmètre
/// non-dispositif-médical) : aucun contrôle, aucune recommandation.
///
/// [trailing] permet d'injecter une action contextuelle (ex. bouton
/// « Terminer » compact en mobile).
class PatientBanner extends StatelessWidget {
  const PatientBanner({super.key, required this.session, this.trailing});

  final ClinicalSession session;
  final Widget? trailing;

  String get _displayName {
    final name = session.patient?.displayName ?? session.patientName;
    return (name == null || name.trim().isEmpty) ? 'Patient' : name.trim();
  }

  String get _initials {
    final parts =
        _displayName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String? get _metaLine {
    final parts = <String>[];
    final age = session.patient?.ageYears;
    if (age != null) parts.add('$age ans');
    final startsAt = session.appointmentStartsAt?.toLocal();
    if (startsAt != null) {
      final hh = startsAt.hour.toString().padLeft(2, '0');
      final mm = startsAt.minute.toString().padLeft(2, '0');
      parts.add('RDV $hh:$mm');
    }
    final phase = session.currentPhase;
    final motif = session.appointmentMotif?.trim();
    if (motif != null && motif.isNotEmpty) {
      parts.add(
        phase == null
            ? motif
            : '$motif — phase ${phase.position}/${phase.phaseCount}',
      );
    } else if (phase != null) {
      parts.add(
        '${phase.planTitle} — phase ${phase.position}/${phase.phaseCount}',
      );
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String get _statusLabel => session.isCancelled
      ? 'Annulée'
      : session.isCompleted
          ? 'Terminée'
          : 'En cours';

  StatusPillVariant get _statusVariant => session.isCancelled
      ? StatusPillVariant.warning
      : session.isCompleted
          ? StatusPillVariant.success
          : StatusPillVariant.info;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final meta = _metaLine;

    return NubiaCard(
      child: Row(
        key: const Key('patient_banner'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          NubiaAvatar(initials: _initials, radius: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _displayName,
                        key: const Key('patient_banner_name'),
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(label: _statusLabel, variant: _statusVariant),
                  ],
                ),
                if (meta != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    key: const Key('patient_banner_meta'),
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (session.medicalAlerts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final alert in session.medicalAlerts)
                        NubiaBadge.label(
                          label: alert.kind == 'allergie'
                              ? 'Allergie ${alert.label}'
                              : alert.label,
                          variant: alert.kind == 'allergie'
                              ? NubiaBadgeVariant.error
                              : NubiaBadgeVariant.warning,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!session.isFinished && session.startedAt != null) ...[
            const SizedBox(width: 12),
            SessionTimer(startedAt: session.startedAt!),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}
