import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Vue caméra du scan QR — SEUL fichier de l'app qui importe mobile_scanner.
///
/// Monté uniquement sur les plateformes supportées (web, macOS, iOS,
/// Android) : sur Windows/Linux ou si la caméra est refusée, l'écran ne
/// montre que la saisie manuelle ([ManualCodeField], toujours visible).
class QrScannerView extends StatelessWidget {
  const QrScannerView({super.key, required this.onCode});

  final ValueChanged<String> onCode;

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
        height: 280,
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
