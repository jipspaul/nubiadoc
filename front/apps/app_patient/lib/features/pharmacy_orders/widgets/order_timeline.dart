import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Timeline verticale des 4 étapes du parcours nominal du click-and-collect.
/// Réservée aux commandes en cours ou retirées — un état terminal
/// (`rejected`/`cancelled`) sort du parcours et ne déroule pas ces étapes
/// (cf. `OrderRejectedCard` et `order_detail_page.dart`, #5351).
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.order});

  final PharmacyOrder order;

  static const _steps = <(PharmacyOrderStatus, String, IconData)>[
    (PharmacyOrderStatus.received, 'Commande reçue', Icons.receipt_long),
    (PharmacyOrderStatus.preparing, 'En cours de préparation', Icons.sync),
    (PharmacyOrderStatus.ready, 'Prête à être retirée', Icons.inventory_2),
    (PharmacyOrderStatus.pickedUp, 'Retirée', Icons.check),
  ];

  int get _currentIndex => switch (order.status) {
        PharmacyOrderStatus.received => 0,
        PharmacyOrderStatus.preparing => 1,
        PharmacyOrderStatus.ready => 2,
        PharmacyOrderStatus.pickedUp => 3,
        PharmacyOrderStatus.rejected || PharmacyOrderStatus.cancelled => -1,
      };

  /// Horodatage `l2` sous le libellé d'une étape franchie (maquette
  /// design-v2, #5347). `preparing` n'a pas de timestamp dédié côté back
  /// (pas de `preparingAt`) : dérivé de `updatedAt` en attendant, comme
  /// suggéré par l'issue — approximatif si la commande a déjà avancé plus
  /// loin, mais préférable à une heure inventée.
  String? _subtitleFor(PharmacyOrderStatus status) {
    switch (status) {
      case PharmacyOrderStatus.received:
        return _relativeInstant(order.createdAt);
      case PharmacyOrderStatus.preparing:
        final count = order.lineCount;
        final time = _hhmm(order.updatedAt);
        return count == null
            ? time
            : '$time · $count médicament${count > 1 ? 's' : ''}';
      case PharmacyOrderStatus.ready:
        final readyAt = order.readyAt;
        return readyAt == null
            ? null
            : '${_hhmm(readyAt)} · vous avez été notifiée';
      case PharmacyOrderStatus.pickedUp:
        final pickedUpAt = order.pickedUpAt;
        return pickedUpAt == null ? null : _hhmm(pickedUpAt);
      case PharmacyOrderStatus.rejected:
      case PharmacyOrderStatus.cancelled:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex;
    if (current == -1) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, step) in _steps.indexed)
          _TimelineStep(
            key: Key('timeline_step_${step.$1.name}'),
            label: step.$2,
            done: index <= current,
            isLast: index == _steps.length - 1,
            current: index == current,
            currentIcon: step.$3,
            subtitle: index <= current
                ? _subtitleFor(step.$1)
                : (index == _steps.length - 1
                    ? 'En attente de votre passage'
                    : null),
          ),
      ],
    );
  }
}

/// « Aujourd'hui à HH:mm », sinon « JJ/MM à HH:mm » (jour non relatif faute
/// de vocabulaire imposé par la maquette au-delà d'« aujourd'hui »).
String _relativeInstant(DateTime utc) {
  final dt = utc.toLocal();
  final now = DateTime.now();
  final today =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final day = today
      ? "Aujourd'hui"
      : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  return '$day à ${_hhmm(utc)}';
}

String _hhmm(DateTime utc) {
  final dt = utc.toLocal();
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    super.key,
    required this.label,
    required this.done,
    required this.isLast,
    required this.current,
    required this.currentIcon,
    this.subtitle,
  });

  final String label;
  final bool done;
  final bool isLast;

  /// Étape en cours (ni terminée ni à venir) — pastille distincte (anneau
  /// `--brand700` + icône spécifique à l'étape) et met le sous-texte en
  /// avant (`--brand700` w600, maquette design-v2 #5347/#5346).
  final bool current;

  /// Icône affichée dans la pastille quand l'étape est courante (jamais un
  /// `check` : cf. maquette design-v2, la pastille « now » distingue le
  /// contenu métier de l'étape d'un simple accompli).
  final IconData currentIcon;

  /// Sous-texte `l2` : horodatage (étape franchie) ou texte d'attente
  /// (étape à venir) — `null` si rien à afficher pour cette étape.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Ligne verticale : émeraude seulement entre deux étapes déjà franchies
    // (« ln done »), grise sinon — la pastille courante n'a pas encore
    // « accompli » son segment suivant.
    final lineColor =
        done && !current ? NubiaColors.brand600 : NubiaColors.n300;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              _TimelineDot(done: done, current: current, icon: currentIcon),
              if (!isLast)
                Expanded(child: Container(width: 2, color: lineColor)),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                    color: done ? null : NubiaColors.n400,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: current ? NubiaColors.brand700 : NubiaColors.n500,
                      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille de l'étape — trois traitements distincts (maquette design-v2,
/// #5346) : « fait » plein émeraude + `check`, « en cours » anneau
/// `--brand700` + icône métier de l'étape, « à venir » bordure `--n300` +
/// `circle` gris.
class _TimelineDot extends StatelessWidget {
  const _TimelineDot({
    required this.done,
    required this.current,
    required this.icon,
  });

  final bool done;
  final bool current;
  final IconData icon;

  static const _size = 24.0;

  @override
  Widget build(BuildContext context) {
    if (current) {
      return Container(
        width: _size,
        height: _size,
        decoration: const BoxDecoration(
          color: NubiaColors.brand50,
          shape: BoxShape.circle,
          border: Border.fromBorderSide(
            BorderSide(color: NubiaColors.brand700, width: 3),
          ),
        ),
        child: Icon(icon, size: 14, color: NubiaColors.brand700),
      );
    }
    if (done) {
      return Container(
        width: _size,
        height: _size,
        decoration: const BoxDecoration(
          color: NubiaColors.brand600,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 14, color: Colors.white),
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
      child: const Icon(Icons.circle, size: 8, color: NubiaColors.n400),
    );
  }
}
