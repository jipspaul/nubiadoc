import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'appointments_bloc.dart';
import 'appointments_event.dart';
import 'appointments_state.dart';

/// Page de recherche praticien + booking.
/// Tab 1 du DashboardPage : recherche → liste → détail créneaux → confirmation.
class AppointmentsPage extends StatelessWidget {
  const AppointmentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppointmentsBloc, AppointmentsState>(
      listener: (context, state) {
        if (state is AppointmentsBookingSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rendez-vous confirmé !')),
          );
          context.read<AppointmentsBloc>().add(const AppointmentsSearchChanged(''));
        }
        if (state is AppointmentsError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: BlocBuilder<AppointmentsBloc, AppointmentsState>(
        builder: (context, state) {
          if (state is AppointmentsInitial) {
            return _SearchInput(key: const Key('search_input'));
          }
          if (state is AppointmentsSearchLoading) {
            return const _SearchInput(loading: true);
          }
          if (state is AppointmentsProvidersLoaded) {
            return _ProvidersList(state: state);
          }
          if (state is AppointmentsSlotsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is AppointmentsSlotsLoaded) {
            return _SlotsView(state: state);
          }
          if (state is AppointmentsBookingLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is AppointmentsError) {
            return _ErrorView(message: state.message);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search input
// ---------------------------------------------------------------------------

class _SearchInput extends StatefulWidget {
  const _SearchInput({super.key, this.loading = false});
  final bool loading;

  @override
  State<_SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends State<_SearchInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Trouver un praticien',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('search_field'),
          controller: _controller,
          decoration: InputDecoration(
            hintText: 'Spécialité, nom, ville…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: widget.loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => context
              .read<AppointmentsBloc>()
              .add(AppointmentsSearchChanged(value)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Providers list
// ---------------------------------------------------------------------------

class _ProvidersList extends StatefulWidget {
  const _ProvidersList({required this.state});
  final AppointmentsProvidersLoaded state;

  @override
  State<_ProvidersList> createState() => _ProvidersListState();
}

class _ProvidersListState extends State<_ProvidersList> {
  String _filterQuery = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _filterQuery.isEmpty
        ? widget.state.providers
        : widget.state.providers
            .where((p) =>
                p.displayName.toLowerCase().contains(_filterQuery.toLowerCase()))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            key: const Key('local_search_field'),
            decoration: const InputDecoration(
              hintText: 'Rechercher un praticien',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _filterQuery = value),
          ),
        ),
        if (filtered.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                key: Key('empty_providers'),
                'Aucun praticien trouvé.',
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final provider = filtered[i];
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(provider.displayName),
                  subtitle: Text(provider.specialty),
                  trailing: provider.distanceKm != null
                      ? Text('${provider.distanceKm!.toStringAsFixed(1)} km')
                      : null,
                  onTap: () => context
                      .read<AppointmentsBloc>()
                      .add(AppointmentsProviderSelected(provider)),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Slots view
// ---------------------------------------------------------------------------

class _SlotsView extends StatelessWidget {
  const _SlotsView({required this.state});
  final AppointmentsSlotsLoaded state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.provider.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(state.provider.specialty),
            ],
          ),
        ),
        if (state.slots.isEmpty)
          const Center(child: Text('Aucun créneau disponible.'))
        else
          Expanded(
            child: ListView.builder(
              itemCount: state.slots.length,
              itemBuilder: (context, i) {
                final slot = state.slots[i];
                final isSelected = state.selectedSlot?.id == slot.id;
                return ListTile(
                  leading: Icon(
                    Icons.access_time,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(_formatDateTime(slot.startsAt)),
                  subtitle: Text(_formatDuration(slot.duration)),
                  selected: isSelected,
                  enabled: slot.isAvailable,
                  onTap: slot.isAvailable
                      ? () => context
                          .read<AppointmentsBloc>()
                          .add(AppointmentsSlotSelected(slot))
                      : null,
                );
              },
            ),
          ),
        if (state.selectedSlot != null) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Motif de consultation',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Ex. : Contrôle annuel, douleur…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => context
                      .read<AppointmentsBloc>()
                      .add(AppointmentsMotifChanged(v)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: state.motif.trim().isEmpty
                        ? null
                        : () => context
                            .read<AppointmentsBloc>()
                            .add(const AppointmentsBookingConfirmed()),
                    child: const Text('Confirmer le rendez-vous'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    final weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'jun',
      'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} — $h:$m';
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final h = d.inHours;
    final min = d.inMinutes.remainder(60);
    return min > 0 ? '${h}h$min' : '${h}h';
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context
                .read<AppointmentsBloc>()
                .add(const AppointmentsSearchChanged('')),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
