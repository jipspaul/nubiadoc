import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pickup_deadline_banner.dart';
import 'pickup_qr_card.dart';

/// Hero « code de retrait » : premier bloc de l'écran quand la commande est
/// prête, sur fond `brand700`, visible sans défiler (#5345).
///
/// Enrobe [PickupQrCard] tel quel (clés `pickup_qr_image` /
/// `pickup_code_text`, contenu du QR inchangé) — ne le réécrit pas.
class PickupReadyHero extends StatelessWidget {
  const PickupReadyHero({super.key, required this.order, required this.token});

  final PharmacyOrder order;
  final String token;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pickup_ready_hero'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NubiaColors.brand700,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'VOTRE COMMANDE EST',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: Colors.white.withValues(alpha: .8),
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Prête à retirer',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 25,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Présentez ce code au comptoir',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: .85),
                ),
          ),
          const SizedBox(height: 16),
          PickupQrCard(token: token),
          const SizedBox(height: 8),
          Text(
            'Ou dictez ce code au pharmacien',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: .8),
                ),
          ),
          if (order.readyAt != null) ...[
            const SizedBox(height: 12),
            PickupDeadlineBanner(order: order),
          ],
        ],
      ),
    );
  }
}
