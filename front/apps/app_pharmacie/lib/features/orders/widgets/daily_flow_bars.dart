import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Neuf tranches horaires égales sur la plage d'ouverture [_openHour]–
/// [_closeHour], bornes reprises de l'axe de la maquette (design-v2, #4917).
const _barCount = 9;
const _openHour = 8;
const _closeHour = 19;
const _axisLabels = ['08h', '12h', '16h', '19h'];

/// Mini-graphe « Flux de la journée » — barres horaires dérivées des
/// `createdAt` de la file (aucun appel réseau supplémentaire, #4917) :
/// information de pilotage (où l'on en est de la journée), pas décoration.
///
/// Masqué si la donnée du jour est insuffisante plutôt que d'afficher des
/// barres à zéro sans signification (jamais de valeur inventée, cf. #4916).
class DailyFlowBars extends StatelessWidget {
  const DailyFlowBars({super.key, required this.orders});

  final List<PharmacyOrder> orders;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final counts = _hourlyBuckets(orders, now);
    final maxCount = counts.fold<int>(0, (max, c) => c > max ? c : max);
    if (maxCount == 0) return const SizedBox.shrink();

    final currentBar = _bucketIndexOf(now);
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    return DecoratedBox(
      key: const Key('daily_flow_bars'),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.insights, size: 18, color: tokens.textTertiary),
                const SizedBox(width: 8),
                Text(
                  'Flux de la journée',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < _barCount; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: FractionallySizedBox(
                        key: Key('daily_flow_bar_$i'),
                        alignment: Alignment.bottomCenter,
                        heightFactor:
                            math.max(0.08, counts[i] / maxCount),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: i == currentBar
                                ? NubiaColors.brand700
                                : NubiaColors.brand200,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final label in _axisLabels)
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: tokens.textTertiary),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Répartit les commandes du jour de [now] dans [_barCount] tranches
/// horaires égales entre [_openHour] et [_closeHour].
List<int> _hourlyBuckets(List<PharmacyOrder> orders, DateTime now) {
  final counts = List<int>.filled(_barCount, 0);
  for (final order in orders) {
    if (!_isSameDay(order.createdAt, now)) continue;
    counts[_bucketIndexOf(order.createdAt)]++;
  }
  return counts;
}

int _bucketIndexOf(DateTime instant) {
  final totalMinutes = (_closeHour - _openHour) * 60;
  final minutesSinceOpen =
      (instant.hour * 60 + instant.minute) - _openHour * 60;
  final clampedMinutes =
      math.max(0, math.min(minutesSinceOpen, totalMinutes - 1));
  final slotMinutes = totalMinutes / _barCount;
  final index = (clampedMinutes / slotMinutes).floor();
  return math.max(0, math.min(index, _barCount - 1));
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
