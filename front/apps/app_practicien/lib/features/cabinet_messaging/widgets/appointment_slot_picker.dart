import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../../router/app_router.dart';

/// Sélecteur de créneau pour "Créer un RDV" depuis une conversation
/// (#4159/#4160). Formulaire "1 clic" : patient/motif sont déjà déduits du
/// fil côté back, seul le créneau reste à choisir.
class AppointmentSlotPicker extends StatefulWidget {
  const AppointmentSlotPicker({super.key});

  /// Ouvre le sélecteur ; retourne le créneau choisi, ou `null` si annulé.
  static Future<Slot?> show(BuildContext context) {
    return showDialog<Slot>(
      context: context,
      builder: (_) => const AppointmentSlotPicker(),
    );
  }

  @override
  State<AppointmentSlotPicker> createState() => _AppointmentSlotPickerState();
}

class _AppointmentSlotPickerState extends State<AppointmentSlotPicker> {
  Slot? _selectedSlot;
  List<Slot> _slots = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    final result = await GetIt.instance<ListBookableSlotsUseCase>()();
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.message;
      }),
      (slots) => setState(() {
        _loading = false;
        _slots = slots.where((s) => s.isAvailable).toList();
      }),
    );
  }

  String _slotLabel(Slot slot) {
    const weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const months = [
      'jan.',
      'fév.',
      'mar.',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sep.',
      'oct.',
      'nov.',
      'déc.',
    ];
    final d = slot.startsAt;
    final h =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]} – $h';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('appointment_slot_picker'),
      title: const Text('Créer un rendez-vous'),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  key: Key('appointment_slot_picker_loading'),
                  child: CircularProgressIndicator(),
                ),
              )
            : _error != null
                ? Text(
                    _error!,
                    key: const Key('appointment_slot_picker_error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  )
                : _slots.isEmpty
                    // #4540 : un « Créer » définitivement grisé sans le
                    // moindre moyen d'avancer est un cul-de-sac. On explique
                    // la cause et on redirige vers l'agenda (où le praticien
                    // ouvre de nouvelles disponibilités), plutôt qu'un
                    // message sec + un bouton mort.
                    ? Column(
                        key: const Key('appointment_slot_picker_empty'),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Aucun créneau disponible dans les prochains '
                            'jours. Ouvrez de nouvelles disponibilités '
                            'depuis l\'agenda pour proposer un rendez-vous.',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key(
                              'appointment_slot_picker_go_to_agenda',
                            ),
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: const Text('Aller à l\'agenda'),
                            onPressed: () {
                              Navigator.of(context).pop();
                              context.go(AppRouter.agenda);
                            },
                          ),
                        ],
                      )
                    : InputDecorator(
                        decoration: const InputDecoration(labelText: 'Créneau'),
                        child: DropdownButton<Slot>(
                          key: const Key('appointment_slot_dropdown'),
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          value: _selectedSlot,
                          hint: const Text('Sélectionner un créneau'),
                          items: _slots
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(_slotLabel(s)),
                                  ))
                              .toList(),
                          onChanged: (s) => setState(() => _selectedSlot = s),
                        ),
                      ),
      ),
      actions: [
        TextButton(
          key: const Key('appointment_slot_picker_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('appointment_slot_picker_confirm'),
          onPressed: _selectedSlot == null
              ? null
              : () => Navigator.of(context).pop(_selectedSlot),
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
