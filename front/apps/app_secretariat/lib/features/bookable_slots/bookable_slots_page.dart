import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'bookable_slots_bloc.dart';
import 'bookable_slots_event.dart';
import 'bookable_slots_state.dart';
import 'create_slot_dialog.dart';

/// Body-only content for bookable slots. Can be embedded in any layout that
/// provides [BookableSlotsBloc] via [BlocProvider] (e.g. [ProShell]
/// bodyBuilder or the full-page [BookableSlotsPage]).
class BookableSlotsBody extends StatefulWidget {
  const BookableSlotsBody({super.key});

  @override
  State<BookableSlotsBody> createState() => _BookableSlotsBodyState();
}

class _BookableSlotsBodyState extends State<BookableSlotsBody> {
  @override
  void initState() {
    super.initState();
    context.read<BookableSlotsBloc>().add(const BookableSlotsLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<BookableSlotsBloc, BookableSlotsState>(
      listenWhen: (_, state) => state is BookableSlotsSlotCreatedSuccess,
      listener: (context, _) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Créneau ajouté')),
        );
      },
      child: BlocBuilder<BookableSlotsBloc, BookableSlotsState>(
        // SlotCreatedSuccess est transitoire : on garde l'affichage précédent
        // pendant le rechargement pour éviter un flash de spinner.
        buildWhen: (_, state) => state is! BookableSlotsSlotCreatedSuccess,
        builder: (context, state) {
          if (state is BookableSlotsLoaded) {
            final slots = state.slots;
            if (slots.isEmpty) {
              return const NubiaEmptyState(
                icon: Icons.event_available_outlined,
                title: 'Aucun créneau',
                subtitle: 'Aucun créneau disponible.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: slots.length,
              itemBuilder: (_, i) => _SlotTile(slot: slots[i]),
            );
          }
          if (state is BookableSlotsError) {
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () => context
                  .read<BookableSlotsBloc>()
                  .add(const BookableSlotsLoadRequested()),
            );
          }
          // BookableSlotsInitial, BookableSlotsLoading
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

class BookableSlotsPage extends StatefulWidget {
  const BookableSlotsPage({super.key});

  @override
  State<BookableSlotsPage> createState() => _BookableSlotsPageState();
}

class _BookableSlotsPageState extends State<BookableSlotsPage> {
  Future<void> _openCreateSlotDialog() async {
    final result = await showDialog<({DateTime startsAt, DateTime endsAt})>(
      context: context,
      builder: (_) => const CreateSlotDialog(),
    );
    if (result == null || !mounted) return;
    context.read<BookableSlotsBloc>().add(
          CreateSlotRequested(
            startsAt: result.startsAt,
            endsAt: result.endsAt,
          ),
        );
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
        onPressed: _openCreateSlotDialog,
        icon: const Icon(Icons.add),
        label: const Text('Créer un créneau'),
      ),
      body: const BookableSlotsBody(),
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
