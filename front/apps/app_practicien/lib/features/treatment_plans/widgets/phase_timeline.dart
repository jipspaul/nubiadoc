import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Frise verticale des phases d'un plan de traitement (#5021) : pastilles +
/// connecteurs, dans l'ordre `position`. Chrome uniquement — le contenu
/// métier de chaque étape reste porté par l'appelant via [PhaseStep.card].
/// Même pattern que `app_patient/features/treatment_plans/widgets/
/// phase_timeline.dart` (#5296). Maquette :
/// `design/v2-screens/praticien-plan-de-traitement.png`.
class PhaseTimeline extends StatelessWidget {
  const PhaseTimeline({super.key, required this.children});

  /// Une entrée par phase, déjà triée par `position` par l'appelant.
  final List<PhaseStep> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Ligne `.ph` d'une phase : colonne gauche `.rail` (pastille + connecteur),
/// colonne droite la carte de phase fournie par l'appelant.
class PhaseStep extends StatelessWidget {
  const PhaseStep({
    super.key,
    required this.status,
    required this.number,
    required this.isLast,
    required this.card,
  });

  /// Statut brut de la phase (`done`, `in_progress`, ou autre = à venir) —
  /// dérive le traitement visuel de la pastille et du connecteur.
  final String status;

  /// Numéro d'ordre affiché dans la pastille pour une phase pas encore
  /// terminée (ordre `position`).
  final int number;

  /// Dernière étape de la frise — pas de connecteur sous sa pastille.
  final bool isLast;

  /// Carte de phase (contenu métier) affichée à droite de la pastille.
  final Widget card;

  bool get _isDone => status == 'done';

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                _PhaseDot(status: status, number: number),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: _isDone ? NubiaColors.brand200 : NubiaColors.n300,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: card,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille `.dot` d'une étape — trois traitements distincts : « terminée »
/// plein `--brand600` + `check`, « en cours » anneau `--n900` 2,5px +
/// numéro, « à venir » bordure `--n300` + numéro `--n500`.
class _PhaseDot extends StatelessWidget {
  const _PhaseDot({required this.status, required this.number});

  final String status;
  final int number;

  static const _size = 26.0;

  @override
  Widget build(BuildContext context) {
    if (status == 'done') {
      return Container(
        width: _size,
        height: _size,
        decoration: const BoxDecoration(
          color: NubiaColors.brand600,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 15, color: Colors.white),
      );
    }

    if (status == 'in_progress') {
      return Container(
        width: _size,
        height: _size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.fromBorderSide(
            BorderSide(color: NubiaColors.n900, width: 2.5),
          ),
        ),
        child: Center(
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: NubiaColors.n900,
            ),
          ),
        ),
      );
    }

    return Container(
      width: _size,
      height: _size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          BorderSide(color: NubiaColors.n300, width: 1),
        ),
      ),
      child: Center(
        child: Text(
          '$number',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: NubiaColors.n500,
          ),
        ),
      ),
    );
  }
}
