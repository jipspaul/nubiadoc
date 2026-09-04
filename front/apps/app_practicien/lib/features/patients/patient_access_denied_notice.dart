import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Bandeau pour un 403 « relation de soin » (garde RLS §14, #4974/#6210) sur
/// un bloc clinique du dossier patient — le praticien n'a pas suivi ce
/// patient, ce n'est pas une panne : distinct de `NubiaErrorWidget` (#6426)
/// dont le bouton « Réessayer » ne peut structurellement jamais aboutir sur
/// un refus déterministe. Même habillage que `_DocumentsReadOnlyNotice`
/// (#4286), une autre limitation permanente du même écran.
class PatientAccessDeniedNotice extends StatelessWidget {
  const PatientAccessDeniedNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: tokens.infoFg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.infoFg),
            ),
          ),
        ],
      ),
    );
  }
}
