import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';

/// Hero « Patient suivant » (#5045, maquette design-v2) : remplace la grille
/// de compteurs en tête du tableau de bord par le patient qui attend déjà en
/// salle — nom, motif, heure, durée, temps d'attente et alertes du dossier,
/// avec les deux actions du praticien (démarrer la consultation / ouvrir le
/// dossier). Masqué quand personne n'attend plutôt que d'inventer un contenu
/// hors maquette : [ProDashboardSummary.nextPatientName] est alors `null`.
class NextPatientHero extends StatelessWidget {
  const NextPatientHero({super.key, required this.summary});

  final ProDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final name = summary.nextPatientName;
    if (name == null || name.isEmpty) {
      return const SizedBox.shrink(key: Key('next_patient_hero_empty'));
    }

    final textTheme = Theme.of(context).textTheme;
    final appointmentTime = summary.nextPatientAppointmentTime;
    final waitingMinutes = summary.nextPatientWaitingMinutes;
    final reason = summary.nextPatientReason;

    return Container(
      key: const Key('next_patient_hero'),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NubiaColors.brand700,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            waitingMinutes == null
                ? 'Patient suivant'
                : 'Patient suivant · en salle d\'attente depuis '
                    '$waitingMinutes min',
            style: textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NubiaAvatar(initials: initialsFrom(name), radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (reason != null && reason.isNotEmpty)
                      Text(
                        reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
              if (appointmentTime != null) ...[
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${appointmentTime.hour.toString().padLeft(2, '0')}:'
                      '${appointmentTime.minute.toString().padLeft(2, '0')}',
                      style: textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (summary.nextPatientDurationMinutes != null)
                      Text(
                        '${summary.nextPatientDurationMinutes} min prévues',
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          if (_hasTags) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (summary.nextPatientAllergyLabel case final allergy?)
                  StatusPill(
                    key: const Key('next_patient_hero_allergy_tag'),
                    label: allergy,
                    variant: StatusPillVariant.error,
                  ),
                if (summary.nextPatientTreatmentPlanCents case final cents?)
                  StatusPill(
                    key: const Key('next_patient_hero_plan_tag'),
                    label: 'Plan en cours · '
                        '${formatQuoteCents(cents, alwaysShowDecimals: true)}',
                    variant: StatusPillVariant.neutral,
                    tabularNums: true,
                  ),
                if (summary.nextPatientLastVisitAt case final lastVisit?)
                  StatusPill(
                    key: const Key('next_patient_hero_last_visit_tag'),
                    label: 'Dernière visite ${_formatShortDate(lastVisit)}',
                    variant: StatusPillVariant.neutral,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('next_patient_hero_start_consultation'),
                  onPressed: () => context.go(AppRouter.consultation),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: NubiaColors.brand700,
                  ),
                  icon: const Icon(Icons.medical_services_outlined),
                  label: const Text(
                    'Démarrer la consultation',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('next_patient_hero_open_file'),
                  onPressed: () => context.go(AppRouter.patients),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                  ),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text(
                    'Ouvrir le dossier',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _hasTags =>
      summary.nextPatientAllergyLabel != null ||
      summary.nextPatientTreatmentPlanCents != null ||
      summary.nextPatientLastVisitAt != null;

  static String _formatShortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}';
}
