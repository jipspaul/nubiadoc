import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Les 4 étapes du cycle nominal, dans l'ordre.
const _kSteps = [
  PharmacyOrderStatus.received,
  PharmacyOrderStatus.preparing,
  PharmacyOrderStatus.ready,
  PharmacyOrderStatus.pickedUp,
];

const _kStepLabels = ['Reçue', 'Préparation', 'Prête', 'Retirée'];

enum _StepState { completed, current, upcoming }

/// Fil des 4 étapes `received → preparing → ready → pickedUp`.
///
/// Purement indicatif : les transitions réelles restent pilotées par
/// [PharmacyOrderStatus.canTransitionTo] côté serveur, le fil ne déclenche
/// aucune action. Pour les états terminaux `rejected`/`cancelled` (dont on
/// ne connaît pas l'étape exacte d'interruption), seule l'étape « Reçue »
/// est marquée franchie — le motif d'arrêt reste porté par le badge de
/// statut existant ([OrderStatusPill]).
class OrderStatusStepper extends StatelessWidget {
  const OrderStatusStepper({super.key, required this.status});

  final PharmacyOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final currentIndex = _kSteps.indexOf(status);
    final current = currentIndex == -1 ? null : currentIndex;

    _StepState stateFor(int i) {
      if (current == null) {
        return i == 0 ? _StepState.completed : _StepState.upcoming;
      }
      if (i < current) return _StepState.completed;
      if (i == current) return _StepState.current;
      return _StepState.upcoming;
    }

    return Row(
      key: const Key('order_status_stepper'),
      children: [
        for (var i = 0; i < _kSteps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: (current != null && i <= current)
                    ? NubiaColors.brand200
                    : NubiaColors.n200,
              ),
            ),
          _StepDot(index: i, label: _kStepLabels[i], state: stateFor(i)),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.label,
    required this.state,
  });

  final int index;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final Widget badge;
    final Color labelColor;
    switch (state) {
      case _StepState.completed:
        badge = const _Dot(
          fill: NubiaColors.brand500,
          child: Icon(Icons.check, size: 16, color: NubiaColors.n0),
        );
        labelColor = NubiaColors.n900;
        break;
      case _StepState.current:
        badge = _Dot(
          borderColor: NubiaColors.n900,
          child: Text(
            '${index + 1}',
            style: textTheme.labelSmall
                ?.copyWith(color: NubiaColors.n900, fontWeight: FontWeight.bold),
          ),
        );
        labelColor = NubiaColors.n900;
        break;
      case _StepState.upcoming:
        badge = _Dot(
          borderColor: NubiaColors.n400,
          child: Text(
            '${index + 1}',
            style: textTheme.labelSmall?.copyWith(color: NubiaColors.n400),
          ),
        );
        labelColor = NubiaColors.n400;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(height: 4),
        Text(
          label,
          key: Key('order_status_step_$index'),
          style: textTheme.bodySmall?.copyWith(color: labelColor),
        ),
      ],
    );
  }
}

/// Pastille ronde 24px — pleine (étape franchie) ou cerclée (courante/à venir).
class _Dot extends StatelessWidget {
  const _Dot({this.fill, this.borderColor, required this.child});

  final Color? fill;
  final Color? borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 2)
            : null,
      ),
      child: child,
    );
  }
}
