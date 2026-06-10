import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/appointment.dart';

/// Écran de préparation du rendez-vous.
///
/// Affiche :
/// - adresse + bouton itinéraire (via url_launcher)
/// - liste des éléments à apporter
/// - code QR de check-in
class AppointmentPreparationPage extends StatelessWidget {
  const AppointmentPreparationPage({
    super.key,
    required this.appointment,
  });

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer mon RDV')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (appointment.address != null)
            AppointmentAddressCard(
              address: appointment.address!,
            ),
          const SizedBox(height: 16),
          if (appointment.itemsToBring.isNotEmpty)
            AppointmentItemsCard(items: appointment.itemsToBring),
          const SizedBox(height: 16),
          if (appointment.qrCode != null)
            AppointmentQrCard(qrCode: appointment.qrCode!),
        ],
      ),
    );
  }
}

/// Carte adresse avec bouton itinéraire.
class AppointmentAddressCard extends StatelessWidget {
  const AppointmentAddressCard({super.key, required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Adresse', style: textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(address, style: textTheme.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('btn_directions'),
              onPressed: () => _openDirections(address),
              icon: const Icon(Icons.directions_outlined),
              label: const Text('Itinéraire'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDirections(String address) async {
    final encoded = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Carte liste des éléments à apporter.
class AppointmentItemsCard extends StatelessWidget {
  const AppointmentItemsCard({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text('À apporter', style: textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item, style: textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte code QR de check-in.
class AppointmentQrCard extends StatelessWidget {
  const AppointmentQrCard({super.key, required this.qrCode});

  final String qrCode;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Check-in QR', style: textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                key: const Key('qr_placeholder'),
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_2,
                      size: 80,
                      color: scheme.onSurface,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      qrCode,
                      style: textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
