import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Écran (minimal) ouvert par le bouton "Modifier" d'un rendez-vous confirmé.
///
/// Le contenu détaillé du flow de modification (choix d'un nouveau créneau)
/// est traité dans un ticket séparé (JEL-22#2) : cet écran affiche pour
/// l'instant le récapitulatif du RDV visé, sans laisser le tap sans action.
class ModifyRdvPage extends StatefulWidget {
  const ModifyRdvPage({super.key, required this.appointmentId, this.useCase});

  final String appointmentId;
  final GetAppointmentByIdUseCase? useCase;

  @override
  State<ModifyRdvPage> createState() => _ModifyRdvPageState();
}

class _ModifyRdvPageState extends State<ModifyRdvPage> {
  late final GetAppointmentByIdUseCase _useCase;
  bool _loading = true;
  String? _error;
  Appointment? _appointment;

  @override
  void initState() {
    super.initState();
    _useCase = widget.useCase ?? GetIt.instance<GetAppointmentByIdUseCase>();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _useCase(widget.appointmentId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.message;
      }),
      (appointment) => setState(() {
        _loading = false;
        _appointment = appointment;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Modifier le rendez-vous')),
        body: const Center(
          key: Key('modify_rdv_loading'),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Modifier le rendez-vous')),
        body: NubiaErrorWidget(
          key: const Key('modify_rdv_error'),
          message: _error!,
          onRetry: _load,
        ),
      );
    }
    final appointment = _appointment!;
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier le rendez-vous')),
      body: ListView(
        key: const Key('modify_rdv_body'),
        padding: const EdgeInsets.all(16),
        children: [
          NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment.practitionerName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${appointment.motif} · ${appointment.practitionerSpecialty}',
                ),
                const SizedBox(height: 8),
                Text(_formatDateTime(appointment.startsAt)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const NubiaEmptyState(
            key: Key('modify_rdv_placeholder'),
            icon: Icons.construction_outlined,
            title: 'La modification en ligne arrive bientôt',
            subtitle:
                'Contactez le cabinet pour changer la date ou l\'heure de ce rendez-vous.',
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const months = [
      'jan',
      'fév',
      'mar',
      'avr',
      'mai',
      'jun',
      'jul',
      'aoû',
      'sep',
      'oct',
      'nov',
      'déc',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} à $h:$m';
  }
}
