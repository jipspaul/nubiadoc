import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'bookable_slots_bloc.dart';
import 'bookable_slots_event.dart';
import 'bookable_slots_state.dart';
import 'create_slot_dialog.dart';

class BookableSlotsPage extends StatefulWidget {
  const BookableSlotsPage({super.key});

  @override
  State<BookableSlotsPage> createState() => _BookableSlotsPageState();
}

class _BookableSlotsPageState extends State<BookableSlotsPage> {
  @override
  void initState() {
    super.initState();
    context.read<BookableSlotsBloc>().add(const BookableSlotsLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Créneaux disponibles'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<BookableSlotsBloc>()
                .add(const BookableSlotsLoadRequested()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_slot_fab'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => BlocProvider.value(
            value: context.read<BookableSlotsBloc>(),
            child: const CreateSlotDialog(),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Créer un créneau'),
      ),
      body: BlocBuilder<BookableSlotsBloc, BookableSlotsState>(
        builder: (context, state) {
          if (state is BookableSlotsLoaded) {
            final slots = state.slots;
            if (slots.isEmpty) {
              return const Center(
                child: Text('Aucun créneau disponible.'),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: slots.length,
              itemBuilder: (_, i) => _SlotTile(slot: slots[i]),
            );
          }
          if (state is BookableSlotsError) {
            return Center(
              child: Text(
                state.message,
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.slot});

  final Slot slot;

  @override
  Widget build(BuildContext context) {
    final start = TimeOfDay.fromDateTime(slot.startsAt);
    final end = TimeOfDay.fromDateTime(slot.endsAt);
    final dateLabel = '${slot.startsAt.day.toString().padLeft(2, '0')}/'
        '${slot.startsAt.month.toString().padLeft(2, '0')}/'
        '${slot.startsAt.year}';
    final timeLabel = '${start.format(context)} – ${end.format(context)}';

    return ListTile(
      leading: Icon(
        slot.isAvailable
            ? Icons.event_available_outlined
            : Icons.event_busy_outlined,
        color: slot.isAvailable ? Colors.green : Colors.grey,
      ),
      title: Text(timeLabel),
      subtitle: Text(dateLabel),
      trailing: slot.isAvailable
          ? const Chip(label: Text('Disponible'))
          : const Chip(label: Text('Indisponible')),
    );
  }
}
