import 'dart:async';

import 'package:flutter/material.dart';

/// Pastille « Séance · 14:32 » du bandeau patient (maquette
/// `bo-praticien-core.jsx`) : durée écoulée depuis le début de séance.
///
/// Affichage pur : la durée est RECALCULÉE à chaque tick depuis [startedAt]
/// (heure serveur) — jamais incrémentée localement, pour éviter toute dérive
/// après un onglet suspendu ou un rebuild.
class SessionTimer extends StatefulWidget {
  const SessionTimer({super.key, required this.startedAt});

  final DateTime startedAt;

  @override
  State<SessionTimer> createState() => _SessionTimerState();
}

class _SessionTimerState extends State<SessionTimer> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _elapsedLabel {
    var elapsed = DateTime.now().difference(widget.startedAt);
    if (elapsed.isNegative) elapsed = Duration.zero;
    final h = elapsed.inHours;
    final m = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const Key('session_timer'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: cs.onPrimary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            'Séance · $_elapsedLabel',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: cs.onPrimary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
