import 'package:flutter/material.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Carte d'une pharmacie (nom, adresse, distance) avec actions
/// « Itinéraire » / « Appeler » — n'affiche que ce qui est disponible
/// (design-v2, #5350).
class PharmacyCard extends StatelessWidget {
  const PharmacyCard({super.key, required this.pharmacy});

  final Pharmacy pharmacy;

  String? get _locationLine {
    final distance = _distanceLabel;
    if (pharmacy.address != null && distance != null) {
      return '${pharmacy.address} · $distance';
    }
    return pharmacy.address ?? distance;
  }

  String? get _distanceLabel {
    final meters = pharmacy.distanceM;
    if (meters == null) return null;
    return meters < 1000
        ? '${meters.round()} m'
        : '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final locationLine = _locationLine;

    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.infoBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.local_pharmacy, color: tokens.infoFg, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pharmacy.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (locationLine != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        locationLine,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: NubiaColors.n500),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (pharmacy.address != null || pharmacy.phone != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (pharmacy.address != null)
                  Expanded(
                    child: NubiaButton(
                      key: const Key('pharmacy_directions_button'),
                      label: 'Itinéraire',
                      icon: Icons.directions,
                      variant: NubiaButtonVariant.secondary,
                      onPressed: () => openMapsDirections(pharmacy.address!),
                    ),
                  ),
                if (pharmacy.address != null && pharmacy.phone != null)
                  const SizedBox(width: 8),
                if (pharmacy.phone != null)
                  Expanded(
                    child: NubiaButton(
                      key: const Key('pharmacy_call_button'),
                      label: 'Appeler',
                      icon: Icons.call,
                      variant: NubiaButtonVariant.secondary,
                      onPressed: () => callPhoneNumber(pharmacy.phone!),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
