import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cancel_rdv_dialog.dart';

class DetailRdvPage extends StatefulWidget {
  const DetailRdvPage({required this.appointment, super.key});
  final Appointment appointment;

  @override
  State<DetailRdvPage> createState() => _DetailRdvPageState();
}

class _DetailRdvPageState extends State<DetailRdvPage> {
  bool _directionsLoading = false;

  void _onCancelTap() {
    showDialog<void>(
      context: context,
      builder: (_) => CancelRdvDialog(appointment: widget.appointment),
    );
  }

  Future<void> _onDirectionsTap() async {
    setState(() => _directionsLoading = true);
    final result = await GetIt.instance<GetDirectionsUseCase>()(
      id: widget.appointment.id,
      mode: 'car',
    );
    if (!mounted) return;
    setState(() => _directionsLoading = false);
    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
      },
      (directions) {
        openDocumentUrl(directions.deeplink).ignore();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appt = widget.appointment;
    return Scaffold(
      appBar: AppBar(title: const Text('Détail du rendez-vous')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appt.motif,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              // #3825 : pas de « · » pendant quand la spécialité est vide.
              appt.practitionerSpecialty.isEmpty
                  ? appt.practitionerName
                  : '${appt.practitionerName} · ${appt.practitionerSpecialty}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (appt.cabinetAddress != null) ...[
              const SizedBox(height: 4),
              Text(
                appt.cabinetAddress!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('directions_button'),
              onPressed: _directionsLoading ? null : _onDirectionsTap,
              icon: _directionsLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.directions_outlined, size: 16),
              label: const Text('Trouver mon chemin'),
            ),
            const Spacer(),
            // #5368 : mêmes règles d'annulation que la liste « Mes RDV »
            // (`if (appointment.canCancel)` dans mes_rdv_page.dart) — sans
            // cette garde, ce bouton restait actif même hors fenêtre
            // d'annulation ou sur un statut déjà terminal, contrairement au
            // reste de la feature.
            if (appt.canCancel)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('cancel_rdv_button'),
                  onPressed: _onCancelTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('Annuler ce RDV'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
