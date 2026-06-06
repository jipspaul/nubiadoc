import 'package:flutter/material.dart';

/// Badge compteur Nubia — cercle coloré affichant un entier > 0.
///
/// Utilisé sur les tuiles dashboard pour indiquer des actions en attente
/// (documents à signer, messages non lus, paiements, questionnaires…).
class NubiaBadge extends StatelessWidget {
  const NubiaBadge({super.key, required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
