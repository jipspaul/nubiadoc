import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'appointments_bloc.dart';
import 'appointments_event.dart';
import 'appointments_state.dart';

/// Page de recherche praticien + booking.
/// Tab 1 du DashboardPage : recherche → carte + liste → créneaux → confirmation.
class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  @override
  void initState() {
    super.initState();
    // Annuaire par défaut au chargement : l'écran n'est jamais vide.
    context
        .read<AppointmentsBloc>()
        .add(const AppointmentsSearchChanged(''));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppointmentsBloc, AppointmentsState>(
      listener: (context, state) {
        if (state is AppointmentsBookingSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rendez-vous confirmé !')),
          );
          context
              .read<AppointmentsBloc>()
              .add(const AppointmentsSearchChanged(''));
        }
        if (state is AppointmentsError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: BlocBuilder<AppointmentsBloc, AppointmentsState>(
        builder: (context, state) {
          // Recherche + résultats : la barre de recherche reste toujours montée.
          if (state is AppointmentsInitial ||
              state is AppointmentsSearchLoading ||
              state is AppointmentsProvidersLoaded) {
            final providers = state is AppointmentsProvidersLoaded
                ? state.providers
                : const <ProviderResult>[];
            return _SearchView(
              providers: providers,
              loading: state is AppointmentsSearchLoading,
            );
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
          if (state is AppointmentsBookingSuccess) {
            return const NubiaEmptyState(
              key: Key('booking_success'),
              icon: Icons.check_circle_outline,
              title: 'Rendez-vous confirmé !',
              subtitle: 'Vous allez recevoir une confirmation.',
            );
          }
          if (state is AppointmentsError) {
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () => context
                  .read<AppointmentsBloc>()
                  .add(const AppointmentsSearchChanged('')),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search view : barre de recherche persistante + carte MapTiler + liste
// ---------------------------------------------------------------------------

class _SearchView extends StatefulWidget {
  const _SearchView({required this.providers, required this.loading});
  final List<ProviderResult> providers;
  final bool loading;

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      context
          .read<AppointmentsBloc>()
          .add(AppointmentsSearchChanged(value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final geoProviders =
        widget.providers.where((p) => p.hasLocation).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            key: const Key('search_field'),
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Spécialité, nom, ville…',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                        setState(() {});
                      },
                    ),
            ),
            onChanged: (v) {
              _onChanged(v);
              setState(() {});
            },
          ),
        ),
        if (geoProviders.isNotEmpty)
          _ProvidersMap(providers: geoProviders),
        Expanded(
          child: widget.loading && widget.providers.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : widget.providers.isEmpty
                  ? const NubiaEmptyState(
                      key: Key('empty_providers'),
                      icon: Icons.person_search_outlined,
                      title: 'Aucun praticien trouvé',
                      subtitle: 'Essayez une autre spécialité ou ville.',
                    )
                  : ListView.separated(
                      key: const Key('providers_list'),
                      itemCount: widget.providers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final provider = widget.providers[i];
                        return ListTile(
                          key: Key('provider_${provider.id}'),
                          leading: const Icon(Icons.person_outline),
                          title: Text(provider.displayName),
                          subtitle: Text(provider.specialty),
                          trailing: provider.distanceKm != null
                              ? Text(
                                  '${provider.distanceKm!.toStringAsFixed(1)} km')
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
// Carte MapTiler (image statique — marqueurs des praticiens géolocalisés)
// ---------------------------------------------------------------------------

class _ProvidersMap extends StatelessWidget {
  const _ProvidersMap({required this.providers});
  final List<ProviderResult> providers;

  LatLng get _center {
    final lat =
        providers.map((p) => p.lat!).reduce((a, b) => a + b) / providers.length;
    final lng =
        providers.map((p) => p.lng!).reduce((a, b) => a + b) / providers.length;
    return LatLng(lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('providers_map'),
      height: 180,
      width: double.infinity,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: _center,
          initialZoom: providers.length == 1 ? 14 : 11,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: ApiConstants.mapTilerTilesUrl(),
            userAgentPackageName: 'health.nubia.patient',
          ),
          MarkerLayer(
            markers: [
              for (final p in providers)
                Marker(
                  point: LatLng(p.lat!, p.lng!),
                  width: 40,
                  height: 40,
                  child: Tooltip(
                    message: p.displayName,
                    child: GestureDetector(
                      onTap: () => context
                          .read<AppointmentsBloc>()
                          .add(AppointmentsProviderSelected(p)),
                      child: Icon(Icons.location_on,
                          color: colorScheme.primary, size: 36),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
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
          const NubiaEmptyState(
            icon: Icons.event_busy_outlined,
            title: 'Aucun créneau disponible.',
          )
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
      'déc'
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
