import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// QR de retrait : encode UNIQUEMENT le token opaque (zéro PII, zéro id
/// métier). Le code en clair est affiché dessous — fallback lisible pour la
/// saisie manuelle au comptoir.
class PickupQrCard extends StatelessWidget {
  const PickupQrCard({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NubiaCard(
      child: Column(
        children: [
          Text('À présenter au comptoir', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Semantics(
            label: 'QR code de retrait de votre commande',
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(
                key: const Key('pickup_qr_image'),
                data: token,
                size: 200,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Code de retrait $token',
            child: SelectableText(
              token,
              key: const Key('pickup_code_text'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
