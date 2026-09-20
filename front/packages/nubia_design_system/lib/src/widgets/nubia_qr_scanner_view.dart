import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Vue caméra du scan QR/Datamatrix, partagée entre les écrans de scan de
/// l'app (retrait pharmacie `app_pharmacie/pickup_scan`, sachet stérilisé
/// `app_practicien/consultation_clinique`, #7180) — SEUL widget du design
/// system qui importe `mobile_scanner`.
///
/// Montée uniquement sur les plateformes supportées ; sur Windows/Linux ou
/// si la caméra est refusée, l'écran appelant doit toujours proposer une
/// saisie manuelle de secours.
class NubiaQrScannerView extends StatelessWidget {
  const NubiaQrScannerView({super.key, required this.onCode, this.height = 280});

  final ValueChanged<String> onCode;
  final double height;

  /// mobile_scanner ne supporte pas Windows/Linux.
  static bool get isSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: MobileScanner(
          onDetect: (capture) {
            final value = capture.barcodes.firstOrNull?.rawValue;
            if (value != null && value.isNotEmpty) {
              onCode(value);
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Caméra indisponible — utilisez la saisie manuelle '
                'ci-dessous.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
