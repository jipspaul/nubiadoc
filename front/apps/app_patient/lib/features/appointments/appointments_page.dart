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
    context.read<AppointmentsBloc>().add(const AppointmentsSearchChanged(''));
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
          // Créneaux/booking d'un praticien : le retour (système, swipe-back,
          // AppBar) doit ramener à la liste des praticiens plutôt que de
          // quitter l'onglet (il n'y a pas de route dédiée à ce sous-écran).
          final isProviderSubScreen = state is AppointmentsSlotsLoading ||
              state is AppointmentsSlotsLoaded ||
              state is AppointmentsBookingLoading;
          return PopScope(
            canPop: !isProviderSubScreen,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              context
                  .read<AppointmentsBloc>()
                  .add(const AppointmentsBackToSearch());
            },
            child: _buildBody(context, state),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppointmentsState state) {
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
  }
}

// ---------------------------------------------------------------------------
// Helpers de présentation (initiales, formatage date/heure)
// ---------------------------------------------------------------------------

const _weekdays = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
const _months = [
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

/// Initiales de repli pour l'avatar (ex. « Dr Claire Lefèvre » → « CL »).
String _initialsOf(String name) {
  final cleaned = name
      .replaceAll(
        RegExp(r'^(Dr|Dr\.|Pr|Pr\.|M\.|Mme|Mlle)\s+', caseSensitive: false),
        '',
      )
      .trim();
  final parts =
      cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final w = parts.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// Jour relatif court (« Aujourd'hui », « Demain » ou « Mar. 3 jun »).
String _relativeDay(DateTime dt) {
  final now = DateTime.now();
  final day = DateTime(dt.year, dt.month, dt.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return "Aujourd'hui";
  if (diff == 1) return 'Demain';
  return '${_weekdays[dt.weekday - 1]} ${dt.day} ${_months[dt.month - 1]}';
}

String _dayHeader(DateTime dt) =>
    '${_weekdays[dt.weekday - 1]} ${dt.day} ${_months[dt.month - 1]}';

String _hhmm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

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
      context.read<AppointmentsBloc>().add(AppointmentsSearchChanged(value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final geoProviders = widget.providers.where((p) => p.hasLocation).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: NubiaSearchBar(
            key: const Key('search_field'),
            controller: _controller,
            hint: 'Spécialité, nom, ville…',
            onChanged: _onChanged,
            onClear: () => _onChanged(''),
          ),
        ),
        if (geoProviders.isNotEmpty) _ProvidersMap(providers: geoProviders),
        Expanded(
          child: widget.loading && widget.providers.isEmpty
              ? const _ProvidersSkeleton()
              : widget.providers.isEmpty
                  ? const NubiaEmptyState(
                      key: Key('empty_providers'),
                      icon: Icons.person_search_outlined,
                      title: 'Aucun praticien trouvé',
                      subtitle: 'Essayez une autre spécialité ou ville.',
                    )
                  : ListView.separated(
                      key: const Key('providers_list'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: widget.providers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final provider = widget.providers[i];
                        return ProviderCard(
                          key: Key('provider_${provider.id}'),
                          name: provider.displayName,
                          specialty: provider.specialty,
                          initials: _initialsOf(provider.displayName),
                          availabilityLabel: provider.nextSlotAt != null
                              ? '1re dispo · ${_relativeDay(provider.nextSlotAt!)}'
                              : null,
                          distance: provider.distanceKm != null
                              ? '${provider.distanceKm!.toStringAsFixed(1)} km'
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

/// Skeleton de chargement : quelques cartes praticien en shimmer.
class _ProvidersSkeleton extends StatelessWidget {
  const _ProvidersSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const NubiaSkeletonLoader(
        height: 84,
        borderRadius: 12,
      ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slots view : en-tête praticien + créneaux SlotChip groupés par jour
// ---------------------------------------------------------------------------

class _SlotsView extends StatelessWidget {
  const _SlotsView({required this.state});
  final AppointmentsSlotsLoaded state;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final borderColor = tokens?.borderSubtle ?? Theme.of(context).dividerColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // En-tête praticien : retour + avatar + identité.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                key: const Key('slots_back'),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Retour',
                onPressed: () => context
                    .read<AppointmentsBloc>()
                    .add(const AppointmentsBackToSearch()),
              ),
              NubiaAvatar(
                initials: _initialsOf(state.provider.displayName),
                radius: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.provider.displayName,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.provider.specialty,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: borderColor),
        if (state.slots.isEmpty)
          const Expanded(
            child: NubiaEmptyState(
              icon: Icons.event_busy_outlined,
              title: 'Aucun créneau disponible.',
              subtitle: 'Revenez plus tard ou choisissez un autre praticien.',
            ),
          )
        else
          Expanded(
            child: _SlotsByDay(state: state),
          ),
        if (state.selectedSlot != null) _BookingPanel(state: state),
      ],
    );
  }
}

/// Liste des créneaux groupés par jour, chaque jour = titre + [SlotChip].
class _SlotsByDay extends StatelessWidget {
  const _SlotsByDay({required this.state});
  final AppointmentsSlotsLoaded state;

  @override
  Widget build(BuildContext context) {
    // Regroupement par jour en préservant l'ordre chronologique d'origine.
    final groups = <DateTime, List<Slot>>{};
    for (final slot in state.slots) {
      final key = DateTime(
        slot.startsAt.year,
        slot.startsAt.month,
        slot.startsAt.day,
      );
      groups.putIfAbsent(key, () => []).add(slot);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _dayHeader(entry.key),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in entry.value)
                SlotChip(
                  label: _hhmm(slot.startsAt),
                  state: !slot.isAvailable
                      ? SlotChipState.unavailable
                      : state.selectedSlot?.id == slot.id
                          ? SlotChipState.selected
                          : SlotChipState.available,
                  onTap: slot.isAvailable
                      ? () => context
                          .read<AppointmentsBloc>()
                          .add(AppointmentsSlotSelected(slot))
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

/// Panneau bas : motif de consultation + CTA de confirmation.
class _BookingPanel extends StatelessWidget {
  const _BookingPanel({required this.state});
  final AppointmentsSlotsLoaded state;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final borderColor = tokens?.borderSubtle ?? Theme.of(context).dividerColor;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Motif de consultation',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          NubiaTextField(
            variant: NubiaTextFieldVariant.multiline,
            maxLines: 2,
            hint: 'Ex. : Contrôle annuel, douleur…',
            onChanged: (v) => context
                .read<AppointmentsBloc>()
                .add(AppointmentsMotifChanged(v)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: NubiaButton(
              key: const Key('confirm_booking_button'),
              label: 'Confirmer le rendez-vous',
              size: NubiaButtonSize.lg,
              icon: Icons.check_rounded,
              onPressed: state.motif.trim().isEmpty
                  ? null
                  : () => context
                      .read<AppointmentsBloc>()
                      .add(const AppointmentsBookingConfirmed()),
            ),
          ),
        ],
      ),
    );
  }
}
