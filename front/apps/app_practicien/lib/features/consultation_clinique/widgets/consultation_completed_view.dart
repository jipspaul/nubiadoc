import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../../router/app_router.dart';

/// Écran de clôture de séance : confirme l'enregistrement, restitue le
/// résultat de `POST …/complete` (devis généré, séances restantes de la
/// phase #4120) et propose les enchaînements (retour agenda, prochaine
/// séance).
class ConsultationCompletedView extends StatelessWidget {
  const ConsultationCompletedView({super.key, this.result});

  final SessionCompleteResult? result;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final sessionsRemaining = result?.sessionsRemaining;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          key: const Key('consultation_completed'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: cs.primary),
            const SizedBox(height: 12),
            Text('Consultation terminée', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              result?.invoiceId != null
                  ? 'Les actes ont été enregistrés et le devis a été '
                      'transmis au patient.'
                  : 'Les actes ont été enregistrés.',
              key: const Key('consultation_completed_subtitle'),
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (sessionsRemaining != null) ...[
              const SizedBox(height: 8),
              NubiaBadge.label(
                key: const Key('sessions_remaining_badge'),
                label: sessionsRemaining > 0
                    ? '$sessionsRemaining séance(s) restante(s) sur la phase'
                    : 'Phase terminée',
                variant: sessionsRemaining > 0
                    ? NubiaBadgeVariant.info
                    : NubiaBadgeVariant.success,
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                NubiaButton(
                  key: const Key('completed_back_to_agenda'),
                  size: NubiaButtonSize.sm,
                  variant: NubiaButtonVariant.secondary,
                  icon: Icons.calendar_today_outlined,
                  label: 'Retour à l\'agenda',
                  onPressed: () => GoRouter.of(context).go(AppRouter.agenda),
                ),
                if (sessionsRemaining != null && sessionsRemaining > 0)
                  NubiaButton(
                    key: const Key('completed_schedule_next'),
                    size: NubiaButtonSize.sm,
                    icon: Icons.event_outlined,
                    label: 'Programmer la prochaine séance',
                    onPressed: () => GoRouter.of(context).go(AppRouter.agenda),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
