import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../consultation_clinique_bloc.dart';
import '../consultation_clinique_event.dart';
import '../sterilization_scan_page.dart';
import '../../../router/app_router.dart';

/// Colonne « Actions » de la vue fauteuil (desktop/tablette) : enchaînements
/// de séance et CTA primaire « Terminer & facturer » pleine largeur
/// (maquette `bo-praticien-core.jsx`).
///
/// « Prescrire une ordonnance » (#4541) et « Étape suivante du plan »
/// (#4120) exigent le patient du contexte enrichi — masqués si absent
/// (payload minimal), jamais de bouton mort.
class SessionActionsPanel extends StatelessWidget {
  const SessionActionsPanel({
    super.key,
    required this.session,
    required this.actionInProgress,
    this.onAddAct,
  });

  final ClinicalSession session;
  final bool actionInProgress;

  /// Amène la zone de saisie d'acte à l'écran (colonne centrale).
  final VoidCallback? onAddAct;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      child: Column(
        key: const Key('session_actions_panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Actions', style: textTheme.titleSmall),
          const SizedBox(height: 12),
          if (onAddAct != null) ...[
            NubiaButton(
              key: const Key('actions_add_act_button'),
              size: NubiaButtonSize.sm,
              variant: NubiaButtonVariant.secondary,
              icon: Icons.add,
              label: 'Ajouter un acte',
              onPressed: session.isFinished ? null : onAddAct,
            ),
            const SizedBox(height: 8),
          ],
          if (session.patient != null) ...[
            NubiaButton(
              key: const Key('prescribe_button'),
              size: NubiaButtonSize.sm,
              variant: NubiaButtonVariant.secondary,
              icon: Icons.medication_outlined,
              label: 'Prescrire une ordonnance',
              // #4541 — ordonnance pré-adressée au patient de la séance.
              onPressed: () => GoRouter.of(context).go(
                '${AppRouter.ordonnances}/new?patientId=${session.patient!.id}',
              ),
            ),
            const SizedBox(height: 8),
            if (session.currentPhase != null) ...[
              NubiaButton(
                key: const Key('next_plan_step_button'),
                size: NubiaButtonSize.sm,
                variant: NubiaButtonVariant.secondary,
                icon: Icons.arrow_forward,
                label: 'Étape suivante du plan',
                onPressed: () => GoRouter.of(context).go(
                  '${AppRouter.patients}/${session.patient!.id}/treatment-plans',
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (session.acts.isNotEmpty) ...[
            NubiaButton(
              key: const Key('sterilization_scan_button'),
              size: NubiaButtonSize.sm,
              variant: NubiaButtonVariant.secondary,
              icon: Icons.qr_code_scanner_outlined,
              // Libellé court : la colonne Actions fait 260-280 px.
              label: 'Scanner une pochette',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SterilizationScanPage(
                    // Dernier acte ajouté = "l'acte en cours" (#4139),
                    // même convention que le surlignage de SessionActRow
                    // (session.acts trié created_at ASC côté back).
                    consultationActId: session.acts.last.id,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Divider(height: 17),
          NubiaButton(
            key: const Key('complete_consultation_button'),
            icon: Icons.check,
            label: 'Terminer & facturer',
            onPressed: actionInProgress || session.isFinished
                ? null
                : () => context.read<ConsultationCliniqueBloc>().add(
                      const ConsultationCliniqueCompleteRequested(),
                    ),
          ),
        ],
      ),
    );
  }
}
