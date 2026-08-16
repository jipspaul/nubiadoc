import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../session/auth_cubit.dart';
import 'appointments_bloc.dart';
import 'appointments_event.dart';
import 'appointments_state.dart';
import 'booking_confirmation_page.dart';
import 'widgets/provider_filters_aside.dart';

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

  // #5359 : panneau de filtres patient `.aside` (recherche web, ≥ écran
  // large) — purement client, ne rejoue pas la recherche réseau (même
  // principe que les facettes backend, calculées indépendamment des
  // filtres actifs).
  Set<String> _asideFilters = <String>{};

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

  /// #5358 : action « Voir sa fiche et ses coordonnées » du bloc « aucun
  /// créneau en ligne » — mène directement à la fiche praticien, sans passer
  /// par le sheet de détail (qui n'a rien à proposer en plus ici).
  void _openProviderProfile(ProviderResult provider) {
    _bloc.add(AppointmentsProviderSelected(provider));
  }

  /// Détail praticien en NubiaBottomSheet : ProviderCard + tarifs indicatifs
  /// + « Voir les créneaux ».
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
          const _IndicativeTariffsCard(),
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
    final filtered = filterProviders(widget.providers, _asideFilters);
    final geoProviders = filtered.where((p) => p.hasLocation).toList();
    final mapAndSheet = Stack(
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
          providers: filtered,
          loading: widget.loading,
          onCardTap: _onProviderFocused,
          onViewProfile: _openProviderProfile,
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
    // Écran large (web) : panneau de filtres patient `.aside` (238 px) à
    // gauche, chaque option avec son compteur de résultats (#5359) — le
    // reste de l'expérience (carte + feuille + recherche) est inchangé.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _kFicheWebBreakpoint) return mapAndSheet;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 238,
              child: ProviderFiltersAside(
                providers: widget.providers,
                selected: _asideFilters,
                onChanged: (next) => setState(() => _asideFilters = next),
              ),
            ),
            Expanded(child: mapAndSheet),
          ],
        );
      },
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
    required this.onViewProfile,
  });

  final List<ProviderResult> providers;
  final bool loading;
  final void Function(ProviderResult) onCardTap;
  final void Function(ProviderResult) onViewProfile;

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
                  onViewProfile: onViewProfile,
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
    required this.onViewProfile,
  });

  final List<ProviderResult> providers;
  final bool loading;
  final ScrollController scrollController;
  final void Function(ProviderResult) onCardTap;
  final void Function(ProviderResult) onViewProfile;

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
          onViewProfile: () => onViewProfile(provider),
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
    // Fiche praticien web (#5360, maquette design-v2
    // patient-web-tunnel-reservation) : au-delà de 960 px, l'agenda devient
    // le contenu principal d'une fiche complète (hero + onglets + panneau
    // latéral) au lieu de la simple liste mobile groupée par jour ci-dessous.
    // La sélection d'un créneau bascule sur le même formulaire de
    // confirmation quelle que soit la largeur : pas de fiche dédiée pour lui.
    if (state.selectedSlot == null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _kFicheWebBreakpoint) {
            return _ProviderProfileWebView(state: state);
          }
          return _SlotsMobileView(state: state, borderColor: borderColor);
        },
      );
    }
    return _SlotsMobileView(state: state, borderColor: borderColor);
  }
}

/// Liste mobile historique : en-tête praticien + créneaux groupés par jour
/// (ou formulaire de confirmation une fois un créneau sélectionné).
class _SlotsMobileView extends StatelessWidget {
  const _SlotsMobileView({required this.state, required this.borderColor});
  final AppointmentsSlotsLoaded state;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
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
        // #5362 : une fois un créneau choisi, le formulaire de confirmation
        // (« Vos informations ») remplace la grille — pas un panneau
        // superposé — pour lui laisser toute la hauteur disponible (et
        // rester scrollable sans déborder sur petit écran).
        Expanded(
          child: state.selectedSlot != null
              ? _BookingPanel(state: state)
              : state.slots.isEmpty
                  ? const NubiaEmptyState(
                      icon: Icons.event_busy_outlined,
                      title: 'Aucun créneau disponible.',
                      subtitle:
                          'Revenez plus tard ou choisissez un autre praticien.',
                    )
                  : _SlotsByDay(state: state),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fiche praticien web (#5360, maquette design-v2
// patient-web-tunnel-reservation, écran « Fiche praticien — l'agenda est le
// contenu principal ») : hero praticien, onglets, agenda semaine (6 jours)
// en contenu principal + panneau latéral cabinet/tarifs/horaires.
// ---------------------------------------------------------------------------

/// Largeur à partir de laquelle la fiche complète remplace la liste mobile.
const double _kFicheWebBreakpoint = 960;

/// Largeur du panneau latéral (maquette : `.side2`, 326 px).
const double _kFicheSidePanelWidth = 326;

const _kFicheTabs = <String>[
  'Prendre rendez-vous',
  'Présentation',
  'Tarifs',
  'Horaires & accès',
];

/// « Aujourd'hui, 14:30 » (maquette, bloc « Prochaine disponibilité »).
String _nextAvailabilityLabel(Slot slot) =>
    '${_relativeDay(slot.startsAt)}, ${_hhmm(slot.startsAt)}';

/// « 11 – 16 août » (maquette, navigation semaine de l'agenda).
String _weekRangeLabel(List<DateTime> days) {
  final first = days.first;
  final last = days.last;
  if (first.month == last.month) {
    return '${first.day} – ${last.day} ${_months[first.month - 1]}';
  }
  return '${first.day} ${_months[first.month - 1]} – '
      '${last.day} ${_months[last.month - 1]}';
}

class _ProviderProfileWebView extends StatefulWidget {
  const _ProviderProfileWebView({required this.state});
  final AppointmentsSlotsLoaded state;

  @override
  State<_ProviderProfileWebView> createState() =>
      _ProviderProfileWebViewState();
}

class _ProviderProfileWebViewState extends State<_ProviderProfileWebView> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final borderColor = tokens?.borderSubtle ?? Theme.of(context).dividerColor;
    return Column(
      key: const Key('fiche_praticien_web'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          key: const Key('fiche_back'),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour',
          onPressed: () => context
              .read<AppointmentsBloc>()
              .add(const AppointmentsBackToSearch()),
        ),
        _ProfileHero(provider: widget.state.provider, slots: widget.state.slots),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ProfileTabBar(
            activeIndex: _tabIndex,
            onChanged: (i) => setState(() => _tabIndex = i),
          ),
        ),
        Divider(height: 1, color: borderColor),
        Expanded(
          child: _tabIndex == 0
              ? _BookingTabBody(state: widget.state)
              : _FicheTabPlaceholder(label: _kFicheTabs[_tabIndex]),
        ),
      ],
    );
  }
}

/// Hero praticien : avatar, `h1` (Fraunces, `displayLarge`), sous-titre,
/// tags et « Prochaine disponibilité » (maquette, bloc `.hero2`).
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.provider, required this.slots});
  final ProviderResult provider;
  final List<Slot> slots;

  // Tags professionnels génériques (maquette verbatim) : comme les tarifs
  // indicatifs (#5361), l'API ne référence pas encore ces attributs par
  // praticien — aucune donnée de santé, uniquement des infos de cabinet.
  static const _tags = <String>[
    'Secteur 1 — tarifs conventionnés',
    'Tiers payant',
    'Nouveaux patients acceptés',
    'Accès PMR',
    'Carte bancaire',
  ];

  Slot? get _nextAvailableSlot {
    final available = slots.where((s) => s.isAvailable).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return available.isEmpty ? null : available.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final nextSlot = _nextAvailableSlot;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NubiaAvatar(initials: _initialsOf(provider.displayName), radius: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  provider.displayName,
                  key: const Key('fiche_hero_name'),
                  style: theme.textTheme.displayLarge,
                ),
                if (provider.specialty.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    provider.specialty,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in _tags)
                      NubiaBadge.label(
                        label: tag,
                        variant: NubiaBadgeVariant.info,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Prochaine disponibilité',
                style:
                    theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                nextSlot != null
                    ? _nextAvailabilityLabel(nextSlot)
                    : 'Aucun créneau',
                key: const Key('fiche_hero_next_availability'),
                textAlign: TextAlign.end,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600, color: cs.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Barre d'onglets simple (maquette, bloc `.tabs2`) : 4 onglets, « Prendre
/// rendez-vous » actif par défaut ([_tabIndex] initialisé à 0).
class _ProfileTabBar extends StatelessWidget {
  const _ProfileTabBar({required this.activeIndex, required this.onChanged});
  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      key: const Key('fiche_tab_bar'),
      children: [
        for (int i = 0; i < _kFicheTabs.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: InkWell(
              key: Key('fiche_tab_$i'),
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          i == activeIndex ? cs.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  _kFicheTabs[i],
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        i == activeIndex ? FontWeight.w600 : FontWeight.w400,
                    color: i == activeIndex ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Contenu des onglets « Présentation »/« Tarifs »/« Horaires & accès » :
/// détaillés dans des tickets dédiés, non couverts par #5360.
class _FicheTabPlaceholder extends StatelessWidget {
  const _FicheTabPlaceholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return NubiaEmptyState(
      key: Key('fiche_tab_placeholder_$label'),
      icon: Icons.info_outline,
      title: label,
      subtitle: 'Disponible prochainement.',
    );
  }
}

/// Onglet « Prendre rendez-vous » : agenda semaine en contenu principal +
/// panneau latéral cabinet/tarifs/horaires (maquette, blocs `.agen`/`.side2`).
class _BookingTabBody extends StatelessWidget {
  const _BookingTabBody({required this.state});
  final AppointmentsSlotsLoaded state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(child: _WeekAgenda(state: state)),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: _kFicheSidePanelWidth,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CabinetCard(provider: state.provider),
                  const SizedBox(height: 16),
                  const _IndicativeTariffsCard(),
                  const SizedBox(height: 16),
                  const _HoursCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Agenda semaine (maquette, bloc `.agen`) : titre, navigation semaine
/// précédente/suivante et 6 colonnes-jour de créneaux réels (`Slot`, déjà
/// chargés par le bloc — filtrage client par fenêtre de 6 jours, sans appel
/// réseau supplémentaire).
class _WeekAgenda extends StatefulWidget {
  const _WeekAgenda({required this.state});
  final AppointmentsSlotsLoaded state;

  @override
  State<_WeekAgenda> createState() => _WeekAgendaState();
}

class _WeekAgendaState extends State<_WeekAgenda> {
  static const _daysPerWeek = 6;

  int _weekOffset = 0;

  DateTime get _weekStart {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.add(Duration(days: _daysPerWeek * _weekOffset));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekStart = _weekStart;
    final days =
        List.generate(_daysPerWeek, (i) => weekStart.add(Duration(days: i)));
    final byDay = <DateTime, List<Slot>>{for (final d in days) d: <Slot>[]};
    for (final slot in widget.state.slots) {
      // #5366 : startsAt est UTC — grouper sur les composants bruts classait
      // un créneau proche de minuit UTC sur le mauvais jour local.
      final local = slot.startsAt.toLocal();
      final key = DateTime(local.year, local.month, local.day);
      byDay[key]?.add(slot);
    }

    return NubiaCard(
      key: const Key('week_agenda'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Choisissez un créneau', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                key: const Key('week_prev'),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Semaine précédente',
                onPressed: _weekOffset == 0
                    ? null
                    : () => setState(() => _weekOffset--),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _weekRangeLabel(days),
                    key: const Key('week_range_label'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              IconButton(
                key: const Key('week_next'),
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Semaine suivante',
                onPressed: () => setState(() => _weekOffset++),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final day in days)
                Expanded(
                  child: _DayColumn(
                    day: day,
                    slots: byDay[day] ?? const [],
                    selectedSlot: widget.state.selectedSlot,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Colonne d'un jour de l'agenda semaine : jour + créneaux disponibles
/// (maquette, colonne de `.wk`), ou « — » si aucun créneau ce jour-là.
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.slots,
    required this.selectedSlot,
  });
  final DateTime day;
  final List<Slot> slots;
  final Slot? selectedSlot;

  bool get _isToday {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final available = slots.where((s) => s.isAvailable).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_weekdays[day.weekday - 1]} ${day.day}',
            textAlign: TextAlign.center,
            style:
                theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (_isToday) ...[
            const SizedBox(height: 2),
            Text(
              "aujourd'hui",
              style: theme.textTheme.labelSmall?.copyWith(color: cs.primary),
            ),
          ],
          const SizedBox(height: 8),
          if (available.isEmpty)
            Text(
              '—',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            for (final slot in available)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SlotChip(
                  label: _hhmm(slot.startsAt),
                  state: selectedSlot?.id == slot.id
                      ? SlotChipState.selected
                      : SlotChipState.available,
                  onTap: () => context
                      .read<AppointmentsBloc>()
                      .add(AppointmentsSlotSelected(slot)),
                ),
              ),
        ],
      ),
    );
  }
}

/// Carte « Cabinet » du panneau latéral (maquette, bloc `.side2`) : adresse
/// réelle du praticien si connue. Détail complet (métro, photo…) hors
/// scope #5360, cf. tickets dédiés.
class _CabinetCard extends StatelessWidget {
  const _CabinetCard({required this.provider});
  final ProviderResult provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NubiaCard(
      key: const Key('fiche_cabinet_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Cabinet',
            style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place_outlined, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  provider.address ?? 'Adresse non renseignée.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Carte « Horaires » du panneau latéral (maquette, bloc `.side2`). Détail
/// complet hors scope #5360, cf. tickets dédiés.
class _HoursCard extends StatelessWidget {
  const _HoursCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NubiaCard(
      key: const Key('fiche_hours_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Horaires',
            style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Détail à venir.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
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
              // Maquette web (#5365) : puce indisponible = contenu « — »,
              // pas l'heure barrée.
              label: slot.isAvailable ? _hhmm(slot.startsAt) : '—',
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

// ---------------------------------------------------------------------------
// Tarif et remboursement — maquette design-v2 patient-web-tunnel-reservation,
// point 7 : « le tarif et le remboursement, avant de réserver ». Montants
// génériques (l'API ne référence pas encore de grille tarifaire par
// praticien) affichés sur la fiche (carte « Tarifs indicatifs ») et dans le
// récapitulatif de confirmation, avant la prise de rendez-vous (#5361).
// ---------------------------------------------------------------------------

/// Ligne clé/valeur alignée (maquette : `.kv2`) — libellé à gauche, valeur en
/// chiffres tabulaires alignée à droite.
class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w500,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

/// Carte « Tarifs indicatifs » de la fiche praticien (maquette, écran
/// « Fiche praticien ») : montants verbatim de la maquette.
class _IndicativeTariffsCard extends StatelessWidget {
  const _IndicativeTariffsCard();

  static const _tariffs = <(String, String)>[
    ('Consultation', '23 €'),
    ('Détartrage', '28,92 €'),
    ('Carie 1 face', '26,97 €'),
    ('Couronne', 'à partir de 500 €'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return NubiaCard(
      key: const Key('indicative_tariffs_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tarifs indicatifs',
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _tariffs.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child:
                  _KeyValueRow(label: _tariffs[i].$1, value: _tariffs[i].$2),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lignes « Tarif indicatif » / « Remboursement » du récapitulatif de
/// confirmation (maquette, écran « Confirmation »), avant de réserver.
/// Vocabulaire de remboursement aligné sur l'app Patient (Assurance Maladie).
class _TariffRecapCard extends StatelessWidget {
  const _TariffRecapCard();

  @override
  Widget build(BuildContext context) {
    return const NubiaCard(
      key: Key('booking_tariff_recap_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KeyValueRow(label: 'Tarif indicatif', value: '23 €'),
          SizedBox(height: 8),
          _KeyValueRow(
            label: 'Remboursement',
            value: '70 % Assurance Maladie',
          ),
        ],
      ),
    );
  }
}

/// Formulaire de confirmation (étape 3 « Vos informations » du tunnel,
/// maquette design-v2 patient-web-tunnel-reservation) : remplace la grille
/// de créneaux une fois une puce sélectionnée. Pour un visiteur anonyme, ce
/// même formulaire crée le compte à la confirmation — jamais avant — dans
/// le même geste que la réservation (#5362).
class _BookingPanel extends StatefulWidget {
  const _BookingPanel({required this.state});
  final AppointmentsSlotsLoaded state;

  @override
  State<_BookingPanel> createState() => _BookingPanelState();
}

class _BookingPanelState extends State<_BookingPanel> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  // #5611 : contrairement aux autres champs du formulaire, ce champ n'avait
  // pas de controller propre — le TextField gérait alors son buffer interne
  // en mode non contrôlé, seul champ du panneau dans ce cas (tous les
  // autres, y compris le champ e-mail du login, utilisent un controller
  // local stable) ; c'est ce champ précis qui perdait son 1er caractère.
  final _motif = TextEditingController();
  final _precisions = TextEditingController();
  DateTime? _dateOfBirth;
  bool _createAccount = true;
  bool _remindersEnabled = true;
  bool _cguAccepted = false;

  static final _phoneRe = RegExp(r'^(\+33|0033|0)[1-9]\d{8}$');
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  // Le hint affiché ("06 12 34 56 78") contient des espaces : on les retire
  // avant validation, même défaut que account_setup_page (#4813-adjacent).
  String get _normalizedPhone => _phone.text.replaceAll(RegExp(r'\s+'), '');
  bool get _phoneValid => _phoneRe.hasMatch(_normalizedPhone);
  bool get _emailValid => _emailRe.hasMatch(_email.text.trim());

  bool get _guestInfoValid =>
      _createAccount &&
      _firstName.text.trim().isNotEmpty &&
      _lastName.text.trim().isNotEmpty &&
      _dateOfBirth != null &&
      _phoneValid &&
      _emailValid &&
      _cguAccepted;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(DateTime.now().year - 30),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('fr'),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  void initState() {
    super.initState();
    _motif.text = widget.state.motif;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _motif.dispose();
    _precisions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    // #5362 : un visiteur anonyme (pas de session patient) voit le groupe
    // « Pour qui est ce rendez-vous ? » + les options de compte ; un patient
    // déjà connecté (2e RDV) ne revoit jamais ce formulaire d'inscription.
    final needsAccount = context.watch<AuthCubit>().state is! AuthAuthenticated;
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final borderColor = tokens?.borderSubtle ?? Theme.of(context).dividerColor;
    final subdued = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final sectionTitle = Theme.of(context)
        .textTheme
        .titleSmall
        ?.copyWith(fontWeight: FontWeight.w600);
    final holdExpiresAt = state.holdExpiresAt;
    final motifValid = state.motif.trim().isNotEmpty;
    final formValid = motifValid && (!needsAccount || _guestInfoValid);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _BookingStepper(),
            const SizedBox(height: 16),
            Text(
              'Il ne reste qu\'une étape',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            // #5363 : sous-titre du formulaire — annonce le verrou de 10 min
            // dès la sélection du créneau (le décompte vivant est plus bas).
            Text('Votre rendez-vous est retenu pendant 10 minutes.',
                style: subdued),
            if (needsAccount) ...[
              const SizedBox(height: 2),
              Text(
                'Créez votre compte pour le confirmer — il vous servira '
                'ensuite à gérer vos rendez-vous, vos documents et vos '
                'devis.',
                style: subdued,
              ),
            ],
            const SizedBox(height: 20),
            const _TariffRecapCard(),
            const SizedBox(height: 20),
            if (needsAccount) ...[
              Text('Pour qui est ce rendez-vous ?', style: sectionTitle),
              const SizedBox(height: 8),
              NubiaTextField(
                key: const Key('booking_first_name'),
                controller: _firstName,
                label: 'Prénom',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              NubiaTextField(
                key: const Key('booking_last_name'),
                controller: _lastName,
                label: 'Nom',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              _BookingDobField(
                value: _dateOfBirth != null ? _formatDate(_dateOfBirth!) : null,
                onTap: _pickDate,
              ),
              const SizedBox(height: 12),
              NubiaTextField(
                key: const Key('booking_phone'),
                controller: _phone,
                variant: NubiaTextFieldVariant.phone,
                label: 'Téléphone mobile',
                hint: '06 12 34 56 78',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              NubiaTextField(
                key: const Key('booking_email'),
                controller: _email,
                label: 'Email',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
            ],
            Text('Motif de la consultation', style: sectionTitle),
            const SizedBox(height: 8),
            NubiaTextField(
              key: const Key('booking_motif'),
              controller: _motif,
              label: 'Motif',
              hint: 'Ex. : Contrôle annuel, douleur…',
              onChanged: (v) => context
                  .read<AppointmentsBloc>()
                  .add(AppointmentsMotifChanged(v)),
            ),
            const SizedBox(height: 12),
            NubiaTextField(
              key: const Key('booking_precisions'),
              controller: _precisions,
              variant: NubiaTextFieldVariant.multiline,
              maxLines: 2,
              label: 'Précisions pour le praticien (facultatif)',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            if (needsAccount) ...[
              NubiaCheckbox(
                key: const Key('booking_create_account'),
                value: _createAccount,
                label: 'Je crée mon compte Nubia',
                onChanged: (v) => setState(() => _createAccount = v),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 30, bottom: 8),
                child: Text(
                  'Un mot de passe vous sera demandé après confirmation. '
                  'Vous pourrez ensuite annuler ou déplacer ce rendez-vous '
                  'vous-même.',
                  style: subdued,
                ),
              ),
            ],
            NubiaCheckbox(
              key: const Key('booking_reminders'),
              value: _remindersEnabled,
              label: 'Rappels de rendez-vous',
              onChanged: (v) => setState(() => _remindersEnabled = v),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 30, bottom: 8),
              child: Text(
                'Par e-mail et SMS, 48 h puis 2 h avant. Modifiable à tout '
                'moment.',
                style: subdued,
              ),
            ),
            if (needsAccount) ...[
              NubiaCheckbox(
                key: const Key('booking_cgu'),
                value: _cguAccepted,
                label: "J'accepte les Conditions Générales d'Utilisation "
                    'et la politique de confidentialité',
                onChanged: (v) => setState(() => _cguAccepted = v),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  'Vos données de santé sont hébergées en France chez un '
                  'hébergeur agréé HDS.',
                  style: subdued,
                ),
              ),
            ],
            if (holdExpiresAt != null) ...[
              const SizedBox(height: 12),
              _HoldCountdown(
                key: ValueKey('hold_countdown_${state.holdToken}'),
                expiresAt: holdExpiresAt,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: NubiaButton(
                key: const Key('confirm_booking_button'),
                label: 'Confirmer le rendez-vous',
                size: NubiaButtonSize.lg,
                icon: Icons.check_rounded,
                onPressed: !formValid
                    ? null
                    : () => context.read<AppointmentsBloc>().add(
                          AppointmentsBookingConfirmed(
                            firstName: _firstName.text.trim(),
                            lastName: _lastName.text.trim(),
                            dateOfBirth: _dateOfBirth,
                            phone: _normalizedPhone,
                            email: _email.text.trim(),
                            precisions: _precisions.text.trim(),
                            createAccount: needsAccount && _createAccount,
                            remindersEnabled: _remindersEnabled,
                            cguAccepted: _cguAccepted,
                          ),
                        ),
              ),
            ),
            const SizedBox(height: 12),
            // Réassurance verbatim maquette.
            Text(
              'Aucune carte bancaire n\'est demandée. Le rendez-vous est '
              'gratuit et annulable en ligne jusqu\'à 24 h avant.',
              textAlign: TextAlign.center,
              style: subdued,
            ),
          ],
        ),
      ),
    );
  }
}

/// Champ date de naissance (JJ / MM / AAAA) : ouvre un [showDatePicker],
/// même pattern que `account_setup_page._DatePickerField`.
class _BookingDobField extends StatelessWidget {
  const _BookingDobField({required this.value, required this.onTap});
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('booking_dob'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: const InputDecoration(
          labelText: 'Date de naissance',
          hintText: 'JJ / MM / AAAA',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today_outlined),
        ),
        child: value != null
            ? Text(value!, style: Theme.of(context).textTheme.bodyMedium)
            : const SizedBox.shrink(),
      ),
    );
  }
}

enum _BookingStepStatus { done, active, upcoming }

/// Fil d'Ariane « Praticien ✓ · Créneau ✓ · Vos informations (actif) ·
/// Confirmé » de la maquette design-v2 (stepper 4 étapes du tunnel web).
class _BookingStepper extends StatelessWidget {
  const _BookingStepper();

  static const _steps = <(String, _BookingStepStatus)>[
    ('Praticien', _BookingStepStatus.done),
    ('Créneau', _BookingStepStatus.done),
    ('Vos informations', _BookingStepStatus.active),
    ('Confirmé', _BookingStepStatus.upcoming),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      key: const Key('booking_stepper'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          if (i > 0) Text('·', style: TextStyle(color: cs.onSurfaceVariant)),
          _BookingStepLabel(label: _steps[i].$1, status: _steps[i].$2),
        ],
      ],
    );
  }
}

class _BookingStepLabel extends StatelessWidget {
  const _BookingStepLabel({required this.label, required this.status});
  final String label;
  final _BookingStepStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = status == _BookingStepStatus.active;
    final done = status == _BookingStepStatus.done;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done ? Icons.check_circle : Icons.circle_outlined,
          size: 14,
          color: (done || active) ? cs.primary : cs.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: active ? cs.primary : cs.onSurfaceVariant,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
        ),
      ],
    );
  }
}

/// Décompte vivant du verrou de 10 min posé sur le créneau sélectionné
/// (#5363) : « Ce créneau vous est réservé pendant X min Y s. Passé ce
/// délai, il redevient disponible. » À zéro, informe l'utilisateur (SnackBar)
/// et relâche la sélection (AppointmentsHoldExpired) pour que le créneau
/// redevienne choisissable.
class _HoldCountdown extends StatefulWidget {
  const _HoldCountdown({required this.expiresAt, super.key});
  final DateTime expiresAt;

  @override
  State<_HoldCountdown> createState() => _HoldCountdownState();
}

class _HoldCountdownState extends State<_HoldCountdown> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = _computeRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Duration _computeRemaining() {
    final diff = widget.expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  void _tick() {
    if (!mounted) return;
    final remaining = _computeRemaining();
    setState(() => _remaining = remaining);
    if (remaining == Duration.zero) {
      _timer?.cancel();
      context.read<AppointmentsBloc>().add(const AppointmentsHoldExpired());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ce créneau vient d\'être libéré, veuillez le sélectionner à '
            'nouveau.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    return Container(
      key: const Key('booking_hold_countdown'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ce créneau vous est réservé pendant $minutes min $seconds s. '
              'Passé ce délai, il redevient disponible.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
