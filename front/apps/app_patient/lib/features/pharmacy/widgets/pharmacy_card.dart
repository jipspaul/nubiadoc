import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Carte d'une pharmacie (nom, adresse, téléphone, distance éventuelle).
class PharmacyCard extends StatelessWidget {
  const PharmacyCard({super.key, required this.pharmacy});

  final Pharmacy pharmacy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pharmacy.name, style: theme.textTheme.titleMedium),
          if (pharmacy.address != null) ...[
            const SizedBox(height: 4),
            Text(pharmacy.address!, style: theme.textTheme.bodyMedium),
          ],
          if (pharmacy.phone != null) ...[
            const SizedBox(height: 4),
            Text(pharmacy.phone!, style: theme.textTheme.bodySmall),
          ],
          if (pharmacy.distanceKm != null) ...[
            const SizedBox(height: 4),
            Text(
              'à ${pharmacy.distanceKm!.toStringAsFixed(1)} km',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
