import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'appointments_bloc.dart';
import 'appointments_event.dart';
import 'appointments_state.dart';
import 'booking_confirmation_page.dart';

/// Page de recherche praticien + booking.
/// Tab 1 du DashboardPage : recherche → carte + liste → créneaux → confirmation.
class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({this.onViewMyAppointments, super.key});

  /// #4534 : appelé quand l'utilisateur tape « Voir mes RDV » sur l'écran
  /// de confirmation — permet au shell (DashboardPage) de basculer l'onglet.
  final VoidCallback? onViewMyAppointments;

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
          _showBookingConfirmation(context, state);
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

  /// #4534 : écran de confirmation dédié (récap praticien/date/motif) au
  /// lieu d'un simple snackbar fugace qui ne rassurait pas assez.
  Future<void> _showBookingConfirmation(
    BuildContext context,
    AppointmentsBookingSuccess state,
  ) async {
    final bloc = context.read<AppointmentsBloc>();
    final viewAppointments = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingConfirmationPage(appointment: state.appointment),
      ),
    );
    if (!mounted) return;
    bloc.add(const AppointmentsSearchChanged(''));
    if (viewAppointments == true) {
      widget.onViewMyAppointments?.call();
    }
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
        icon: Icons.schedule_outlined,
        title: 'Demande envoyée',
        subtitle: 'Le cabinet doit confirmer votre rendez-vous. '
            'Vous serez notifié dès sa validation.',
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
///
/// #3856 : `dt` vient de DateTime.parse() sur un ISO avec offset +00:00 →
/// isUtc == true. Lire .day/.weekday/.hour bruts affiche la date/heure UTC
/// au lieu de locale (-2h en été/-1h en hiver pour Europe/Paris) — un
/// créneau 23h30 Paris (21h30 UTC) resterait classé sur le mauvais jour, un
/// créneau 13h Paris (11h UTC) serait classé « Matin ».
String _relativeDay(DateTime utc) {
  final dt = utc.toLocal();
  final now = DateTime.now();
  final day = DateTime(dt.year, dt.month, dt.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return "Aujourd'hui";
  if (diff == 1) return 'Demain';
  return '${_weekdays[dt.weekday - 1]} ${dt.day} ${_months[dt.month - 1]}';
}

String _dayHeader(DateTime utc) {
  final dt = utc.toLocal();
  return '${_weekdays[dt.weekday - 1]} ${dt.day} ${_months[dt.month - 1]}';
}

String _hhmm(DateTime utc) {
  final dt = utc.toLocal();
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Search view : expérience MAP-CENTRIC (façon Waze/Google Maps)
//   • carte MapTiler plein écran + pins praticiens (clustering simple)
//   • barre de recherche flottante + chips de filtres rapides
//   • bottom sheet glissable listant les ProviderCard (snap 12/45/90 %)
//   • recherche langage naturel via POST /v1/search/parse (repli texte brut)
// ---------------------------------------------------------------------------

/// Filtre rapide (chip) : libellé, icône et terme injecté dans la recherche.
class _QuickFilter {
  const _QuickFilter(this.key, this.label, this.icon, this.query);
  final String key;
  final String label;
  final IconData icon;
  final String query;
}

const _quickFilters = <_QuickFilter>[
  _QuickFilter(
      'dispo', 'Disponible', Icons.event_available_outlined, 'disponible'),
  _QuickFilter('teleconsult', 'Téléconsult', Icons.videocam_outlined,
      'téléconsultation'),
  _QuickFilter('secteur1', 'Secteur 1', Icons.euro_outlined, 'secteur 1'),
  _QuickFilter('generaliste', 'Généraliste', Icons.medical_services_outlined,
      'médecin généraliste'),
  _QuickFilter('dentiste', 'Dentiste', Icons.masks_outlined, 'dentiste'),
];

/// Centre par défaut de la carte quand aucun praticien géolocalisé (Paris).
const _defaultCenter = LatLng(48.8566, 2.3522);

class _SearchView extends StatefulWidget {
  const _SearchView({required this.providers, required this.loading});
  final List<ProviderResult> providers;
  final bool loading;

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final _controller = TextEditingController();
  final _mapController = MapController();
  Timer? _debounce;

  final Set<String> _activeFilters = <String>{};
  String? _interpretation;
  bool _parsing = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _mapController.dispose();
    super.dispose();
  }

  AppointmentsBloc get _bloc => context.read<AppointmentsBloc>();

  /// Recherche « propre » = texte libre + termes des chips actifs.
  String _composedQuery([String? overrideText]) {
    final parts = <String>[(overrideText ?? _controller.text).trim()];
    for (final f in _quickFilters) {
      if (_activeFilters.contains(f.key)) parts.add(f.query);
    }
    return parts.where((p) => p.isNotEmpty).join(' ').trim();
  }

  /// Frappe au clavier : recherche live débattue sur le texte + chips actifs.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _bloc.add(AppointmentsSearchChanged(_composedQuery(value)));
    });
  }

  /// Validation (clavier « rechercher ») : interprétation langage naturel via
  /// /v1/search/parse, puis relance de la recherche avec les filtres extraits.
  /// Repli : si l'endpoint échoue, on passe le texte brut à la recherche.
  Future<void> _onSubmitted(String value) async {
    _debounce?.cancel();
    final raw = _composedQuery(value);
    final gi = GetIt.instance;
    if (raw.isEmpty || !gi.isRegistered<ParseSearchUseCase>()) {
      setState(() => _interpretation = null);
      _bloc.add(AppointmentsSearchChanged(raw));
      return;
    }
    setState(() => _parsing = true);
    final result = await gi<ParseSearchUseCase>().call(raw);
    if (!mounted) return;
    result.fold(
      (_) {
        // Endpoint indisponible → repli sur le texte brut, l'écran tient.
        setState(() {
          _parsing = false;
          _interpretation = null;
        });
        _bloc.add(AppointmentsSearchChanged(raw));
      },
      (parsed) {
        final effective =
            parsed.query.q.trim().isEmpty ? raw : parsed.query.q.trim();
        setState(() {
          _parsing = false;
          _interpretation = parsed.interpretation.trim().isEmpty
              ? null
              : parsed.interpretation.trim();
        });
        _bloc.add(AppointmentsSearchChanged(effective));
      },
    );
  }

  void _toggleFilter(_QuickFilter filter) {
    setState(() {
      if (!_activeFilters.remove(filter.key)) _activeFilters.add(filter.key);
    });
    _debounce?.cancel();
    _bloc.add(AppointmentsSearchChanged(_composedQuery()));
  }

  /// Tap sur un pin ou une carte : recentre la carte et ouvre le détail.
  void _onProviderFocused(ProviderResult provider) {
    if (provider.hasLocation) {
      _mapController.move(LatLng(provider.lat!, provider.lng!), 15);
    }
    _openProviderSheet(provider);
  }

  /// Détail praticien en NubiaBottomSheet : ProviderCard + « Voir les créneaux ».
  void _openProviderSheet(ProviderResult provider) {
    final bloc = _bloc; // capturé : le sheet est hors de l'arbre BlocProvider.
    NubiaBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProviderCard(
            key: Key('sheet_provider_${provider.id}'),
            name: provider.displayName,
            specialty: provider.specialty,
            initials: _initialsOf(provider.displayName),
            availabilityLabel: provider.nextSlotAt != null
                ? '1re dispo · ${_relativeDay(provider.nextSlotAt!)}'
                : null,
            distance: provider.distanceKm != null
                ? '${provider.distanceKm!.toStringAsFixed(1)} km'
                : null,
          ),
          const SizedBox(height: 16),
          NubiaButton(
            key: const Key('sheet_see_slots'),
            label: 'Voir les créneaux',
            size: NubiaButtonSize.lg,
            icon: Icons.event_outlined,
            onPressed: () {
              Navigator.of(context).pop();
              bloc.add(AppointmentsProviderSelected(provider));
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final geoProviders = widget.providers.where((p) => p.hasLocation).toList();
    return Stack(
      children: [
        // 1. Carte plein écran (façon Waze) avec pins/clusters.
        Positioned.fill(
          child: _ProvidersMap(
            controller: _mapController,
            providers: geoProviders,
            onProviderTap: _onProviderFocused,
          ),
        ),
        // 2. Feuille de résultats glissable superposée à la carte.
        _ResultsSheet(
          providers: widget.providers,
          loading: widget.loading,
          onCardTap: _onProviderFocused,
        ),
        // 3. Barre de recherche flottante + bandeau + chips (au-dessus de tout).
        _FloatingSearchHeader(
          controller: _controller,
          parsing: _parsing,
          interpretation: _interpretation,
          activeFilters: _activeFilters,
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
          onClear: () => _onChanged(''),
          onToggleFilter: _toggleFilter,
          onDismissInterpretation: () => setState(() => _interpretation = null),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// En-tête flottant : barre de recherche + bandeau interprétation + chips
// ---------------------------------------------------------------------------

class _FloatingSearchHeader extends StatelessWidget {
  const _FloatingSearchHeader({
    required this.controller,
    required this.parsing,
    required this.interpretation,
    required this.activeFilters,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onToggleFilter,
    required this.onDismissInterpretation,
  });

  final TextEditingController controller;
  final bool parsing;
  final String? interpretation;
  final Set<String> activeFilters;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final ValueChanged<_QuickFilter> onToggleFilter;
  final VoidCallback onDismissInterpretation;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barre de recherche surélevée (ombre douce), style flottant.
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: NubiaSearchBar(
                  key: const Key('search_field'),
                  controller: controller,
                  hint: 'Dentiste secteur 1 près de Bastille…',
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  onClear: onClear,
                ),
              ),
              if (parsing || interpretation != null) ...[
                const SizedBox(height: 8),
                _InterpretationBanner(
                  parsing: parsing,
                  text: interpretation,
                  onDismiss: onDismissInterpretation,
                ),
              ],
              const SizedBox(height: 8),
              // Chips de filtres rapides en scroll horizontal.
              SizedBox(
                height: 34,
                child: ListView.separated(
                  key: const Key('quick_filters'),
                  scrollDirection: Axis.horizontal,
                  itemCount: _quickFilters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final f = _quickFilters[i];
                    // Fond opaque derrière le chip : les chips non
                    // sélectionnées ont un fond transparent (NubiaChip), ce
                    // qui les rend illisibles superposées à la carte (surtout
                    // en dark mode où le style de carte reste clair).
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(17),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: NubiaChip(
                        label: f.label,
                        icon: f.icon,
                        selected: activeFilters.contains(f.key),
                        onTap: () => onToggleFilter(f),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bandeau « interprétation » sous la barre (source langage naturel).
class _InterpretationBanner extends StatelessWidget {
  const _InterpretationBanner({
    required this.parsing,
    required this.text,
    required this.onDismiss,
  });

  final bool parsing;
  final String? text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('search_interpretation'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          if (parsing)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            )
          else
            Icon(Icons.auto_awesome, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parsing ? 'Interprétation de votre recherche…' : (text ?? ''),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
          ),
          if (!parsing) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onDismiss,
              customBorder: const CircleBorder(),
              child: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feuille de résultats glissable (DraggableScrollableSheet)
// ---------------------------------------------------------------------------

class _ResultsSheet extends StatelessWidget {
  const _ResultsSheet({
    required this.providers,
    required this.loading,
    required this.onCardTap,
  });

  final List<ProviderResult> providers;
  final bool loading;
  final void Function(ProviderResult) onCardTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final borderColor = tokens?.borderSubtle ?? Theme.of(context).dividerColor;
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.12,
      maxChildSize: 0.9,
      snap: true,
      snapSizes: const [0.12, 0.45, 0.9],
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            children: [
              // Poignée de la feuille.
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (providers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${providers.length} praticien'
                      '${providers.length > 1 ? 's' : ''}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              Expanded(
                child: _ResultsContent(
                  providers: providers,
                  loading: loading,
                  scrollController: scrollController,
                  onCardTap: onCardTap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResultsContent extends StatelessWidget {
  const _ResultsContent({
    required this.providers,
    required this.loading,
    required this.scrollController,
    required this.onCardTap,
  });

  final List<ProviderResult> providers;
  final bool loading;
  final ScrollController scrollController;
  final void Function(ProviderResult) onCardTap;

  @override
  Widget build(BuildContext context) {
    // Chargement initial : skeletons en shimmer.
    if (loading && providers.isEmpty) {
      return ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => const NubiaSkeletonLoader(
          height: 84,
          borderRadius: 12,
        ),
      );
    }
    // Vide : état DS, mais dans une liste scrollable (drag de la feuille).
    if (providers.isEmpty) {
      return ListView(
        controller: scrollController,
        children: const [
          SizedBox(height: 24),
          NubiaEmptyState(
            key: Key('empty_providers'),
            icon: Icons.person_search_outlined,
            title: 'Aucun praticien trouvé',
            subtitle: 'Essayez une autre spécialité ou ville.',
          ),
        ],
      );
    }
    return ListView.separated(
      key: const Key('providers_list'),
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: providers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final provider = providers[i];
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
          onTap: () => onCardTap(provider),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Carte MapTiler plein écran + pins praticiens (clustering pixel simple)
// ---------------------------------------------------------------------------

class _ProvidersMap extends StatelessWidget {
  const _ProvidersMap({
    required this.controller,
    required this.providers,
    required this.onProviderTap,
  });

  final MapController controller;
  final List<ProviderResult> providers;
  final void Function(ProviderResult) onProviderTap;

  LatLng get _center {
    if (providers.isEmpty) return _defaultCenter;
    final lat =
        providers.map((p) => p.lat!).reduce((a, b) => a + b) / providers.length;
    final lng =
        providers.map((p) => p.lng!).reduce((a, b) => a + b) / providers.length;
    return LatLng(lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: const Key('providers_map'),
      child: FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCenter: _center,
          initialZoom: providers.length == 1 ? 14 : 12,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom |
                InteractiveFlag.drag |
                InteractiveFlag.doubleTapZoom |
                InteractiveFlag.flingAnimation,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: ApiConstants.mapTilerTilesUrl(
              dark: Theme.of(context).brightness == Brightness.dark,
            ),
            userAgentPackageName: 'health.nubia.patient',
          ),
          _ClusterLayer(
            providers: providers,
            controller: controller,
            onProviderTap: onProviderTap,
          ),
        ],
      ),
    );
  }
}

/// Couche de marqueurs avec clustering « pixel » simple : les pins proches à
/// l'écran (grille ~76 px) sont regroupés en une bulle avec le compte. Se
/// reconstruit à chaque changement de caméra via [MapCamera.of].
///
/// La grille est calculée via [MapCamera.project] (coordonnées de projection
/// pures, dépendant uniquement du zoom) plutôt que via
/// [MapCamera.latLngToScreenPoint] (qui inclut le centre courant). Un pan pur
/// ne fait donc plus dériver les cellules de la grille : sans ce choix, les
/// pins proches d'une frontière de cellule changeaient de bucket à chaque
/// frame de défilement, faisant sursauter les clusters.
class _ClusterLayer extends StatelessWidget {
  const _ClusterLayer({
    required this.providers,
    required this.controller,
    required this.onProviderTap,
  });

  final List<ProviderResult> providers;
  final MapController controller;
  final void Function(ProviderResult) onProviderTap;

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) return const MarkerLayer(markers: []);
    final camera = MapCamera.of(context);
    const cell = 76.0;
    final buckets = <String, List<ProviderResult>>{};
    for (final p in providers) {
      final pt = camera.project(LatLng(p.lat!, p.lng!));
      final key = '${(pt.x / cell).floor()}:${(pt.y / cell).floor()}';
      buckets.putIfAbsent(key, () => <ProviderResult>[]).add(p);
    }

    final markers = <Marker>[];
    for (final group in buckets.values) {
      if (group.length == 1) {
        final p = group.first;
        markers.add(Marker(
          point: LatLng(p.lat!, p.lng!),
          width: 46,
          height: 46,
          alignment: Alignment.topCenter,
          child: _ProviderPin(
            label: p.displayName,
            onTap: () => onProviderTap(p),
          ),
        ));
      } else {
        final lat =
            group.map((p) => p.lat!).reduce((a, b) => a + b) / group.length;
        final lng =
            group.map((p) => p.lng!).reduce((a, b) => a + b) / group.length;
        final center = LatLng(lat, lng);
        markers.add(Marker(
          point: center,
          width: 48,
          height: 48,
          child: _ClusterBubble(
            count: group.length,
            onTap: () =>
                controller.move(center, (camera.zoom + 2).clamp(1.0, 18.0)),
          ),
        ));
      }
    }
    return MarkerLayer(markers: markers);
  }
}

/// Pin émeraude d'un praticien géolocalisé.
class _ProviderPin extends StatelessWidget {
  const _ProviderPin({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Icon(Icons.location_on, size: 44, color: cs.primary),
            Positioned(
              top: 8,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bulle de cluster (compte de praticiens regroupés).
class _ClusterBubble extends StatelessWidget {
  const _ClusterBubble({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primary,
          shape: BoxShape.circle,
          border: Border.all(color: cs.surface, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          '$count',
          style: TextStyle(
            color: cs.onPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 14,
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
                    // #3825 : pas de ligne (ni espace résiduel) quand la
                    // spécialité est vide.
                    if (state.provider.specialty.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        state.provider.specialty,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
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
      // #5366 : startsAt est UTC (isUtc == true) — grouper sur les
      // composants bruts classait un créneau proche de minuit UTC sur le
      // mauvais jour local (ex : 23h30 UTC = 01h30 Paris le lendemain).
      final localStartsAt = slot.startsAt.toLocal();
      final key = DateTime(
        localStartsAt.year,
        localStartsAt.month,
        localStartsAt.day,
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
          // Sous-groupes matin / après-midi (affichés seulement si non vides)
          // pour scanner encore plus vite, façon Doctolib.
          ..._buildPeriods(context, entry.value),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  /// Découpe une journée en « Matin » (< 12 h) et « Après-midi » (>= 12 h) ;
  /// chaque période non vide = petit sous-titre + grille de [SlotChip].
  List<Widget> _buildPeriods(BuildContext context, List<Slot> slots) {
    final periods = <(String, List<Slot>)>[
      // #3856 : startsAt est UTC (isUtc == true) — grouper sur .hour brut
      // classait un créneau 13h Paris (11h UTC) en « Matin ».
      ('Matin', slots.where((s) => s.startsAt.toLocal().hour < 12).toList()),
      (
        'Après-midi',
        slots.where((s) => s.startsAt.toLocal().hour >= 12).toList()
      ),
    ];
    return [
      for (final (label, periodSlots) in periods)
        if (periodSlots.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          _slotWrap(context, periodSlots),
          const SizedBox(height: 12),
        ],
    ];
  }

  /// Grille (Wrap) de [SlotChip] conservant l'état de sélection courant.
  ///
  /// [SlotChip] centre son contenu et s'étirerait à toute la largeur dispo
  /// dans un [Wrap] (→ 1 chip/ligne). On l'enveloppe dans [IntrinsicWidth]
  /// pour qu'il garde une largeur intrinsèque compacte et que plusieurs
  /// créneaux tiennent par ligne (vraie grille, façon Doctolib).
  Widget _slotWrap(BuildContext context, List<Slot> slots) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final slot in slots)
          IntrinsicWidth(
            child: SlotChip(
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
          ),
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
