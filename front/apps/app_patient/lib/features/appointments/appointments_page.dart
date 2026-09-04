import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
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
  const AppointmentsPage({
    this.onViewMyAppointments,
    this.initialQuery,
    this.deepLinkProviderId,
    this.deepLinkSlotId,
    super.key,
  });

  /// #4534 : appelé quand l'utilisateur tape « Voir mes RDV » sur l'écran
  /// de confirmation — permet au shell (DashboardPage) de basculer l'onglet.
  final VoidCallback? onViewMyAppointments;

  /// #5269 : nom du praticien pré-rempli quand on arrive via « Reprendre
  /// RDV » (Mes RDV · historique) — repart de la même recherche, sans forcer
  /// de sélection automatique (l'utilisateur choisit toujours dans la liste).
  final String? initialQuery;

  /// #6459 : `providerId`/`slotId` d'un lien de créneau du tunnel SSR
  /// (`/appointments?providerId=…&slotId=…`, `api/src/web_tunnel/`) — quand
  /// présent, l'écran saute la recherche générique et ouvre directement le
  /// praticien du lien, créneau présélectionné. [deepLinkSlotId] seul, sans
  /// [deepLinkProviderId], est ignoré (le SSR émet toujours les deux).
  final String? deepLinkProviderId;
  final String? deepLinkSlotId;

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  // #5337 : `_BookingPanel` est présenté en `NubiaBottomSheet` modal (au lieu
  // de remplacer la grille de créneaux inline) — la grille reste montée et
  // stable derrière. #5336 : la feuille ne s'ouvre plus automatiquement dès
  // qu'un créneau est sélectionné — la grille affiche d'abord une barre
  // collante « Continuer » (`_ContinueBar`) qui l'ouvre explicitement
  // (`_openBookingSheet`). Ces deux champs suivent la feuille ouverte pour la
  // refermer proactivement si l'écran créneaux disparaît pendant qu'elle est
  // affichée (ex. changement d'onglet du shell, qui démonte AppointmentsPage
  // sans repasser par un pop).
  bool _sheetOpen = false;
  NavigatorState? _sheetNavigator;

  @override
  void initState() {
    super.initState();
    final deepLinkProviderId = widget.deepLinkProviderId;
    if (deepLinkProviderId != null) {
      // #6459 : lien de créneau du tunnel SSR — praticien + créneau du lien
      // directement, jamais l'annuaire par défaut.
      context.read<AppointmentsBloc>().add(AppointmentsDeepLinkRequested(
            providerId: deepLinkProviderId,
            slotId: widget.deepLinkSlotId,
          ));
      return;
    }
    // Annuaire par défaut au chargement : l'écran n'est jamais vide.
    context
        .read<AppointmentsBloc>()
        .add(AppointmentsSearchChanged(widget.initialQuery ?? ''));
  }

  @override
  void dispose() {
    if (_sheetOpen) _sheetNavigator?.maybePop();
    super.dispose();
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
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _syncBookingSheet(context, state));
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

  /// Referme proactivement la feuille de confirmation si l'écran créneaux
  /// disparaît pendant qu'elle est affichée (ex. changement d'onglet du
  /// shell, qui démonte `AppointmentsPage` sans repasser par un pop) —
  /// appelé après chaque build. #5336 : ne l'ouvre plus automatiquement dès
  /// qu'un créneau est sélectionné, voir `_ContinueBar`/`_openBookingSheet`.
  void _syncBookingSheet(BuildContext context, AppointmentsState state) {
    if (!mounted) return;
    if (_sheetOpen && state is! AppointmentsSlotsLoaded) {
      _sheetNavigator?.maybePop();
    }
  }

  /// #5337 : `_BookingPanel` (récap + motif + CTA) en `NubiaBottomSheet`
  /// modal — scrim assombri + poignée du DS, grille de créneaux stable
  /// derrière. `AppointmentsBloc`/`AuthCubit` sont recapturés puis
  /// re-fournis dans la feuille : elle est ouverte hors de l'arbre
  /// `BlocProvider` de l'onglet (même contrainte que `_openProviderSheet`).
  /// #5336 : déclenchée par le bouton « Continuer » de `_ContinueBar`, plus
  /// automatiquement à la sélection du créneau.
  Future<void> _openBookingSheet(BuildContext context) async {
    if (_sheetOpen) return;
    final bloc = context.read<AppointmentsBloc>();
    final authCubit = context.read<AuthCubit>();
    _sheetOpen = true;
    _sheetNavigator = Navigator.of(context);
    await NubiaBottomSheet.show(
      context: context,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AppointmentsBloc>.value(value: bloc),
          BlocProvider<AuthCubit>.value(value: authCubit),
        ],
        child: BlocBuilder<AppointmentsBloc, AppointmentsState>(
          builder: (sheetContext, sheetState) {
            if (sheetState is! AppointmentsSlotsLoaded ||
                sheetState.selectedSlot == null) {
              return const SizedBox.shrink();
            }
            return _BookingPanel(
              state: sheetState,
              onModifier: () => Navigator.of(sheetContext).maybePop(),
            );
          },
        ),
      ),
    );
    _sheetOpen = false;
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
      final slotsByProvider = state is AppointmentsProvidersLoaded
          ? state.slotsByProvider
          : const <String, List<Slot>>{};
      return _SearchView(
        providers: providers,
        slotsByProvider: slotsByProvider,
        loading: state is AppointmentsSearchLoading,
        initialQuery: widget.initialQuery,
      );
    }
    if (state is AppointmentsSlotsLoading) {
      return _SlotsLoadingView(provider: state.provider);
    }
    if (state is AppointmentsSlotsLoaded) {
      return _SlotsView(
        state: state,
        onContinue: () => _openBookingSheet(context),
      );
    }
    if (state is AppointmentsBookingLoading) {
      return _BookingProgressView(state: state);
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

const _monthsFull = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

const _weekdaysFull = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

/// Libellé `.t1` de la carte récap créneau (#5338) : « Jeudi 13 août · 14:30 »
/// — jour complet + quantième + mois complet + heure, tous en heure locale
/// (#3856).
String _slotRecapDateLabel(DateTime utc) {
  final dt = utc.toLocal();
  return '${_weekdaysFull[dt.weekday - 1]} ${dt.day} '
      '${_monthsFull[dt.month - 1]} · ${_hhmm(utc)}';
}

/// Libellé `.l1` de la barre collante « Continuer » (maquette design-v2
/// patient-re-servation, #5336) : « Jeudi 13 août à 14:30 » — jour + mois
/// complets, heure locale (#3856).
String _continueBarDateLabel(DateTime utc) {
  final dt = utc.toLocal();
  return '${_weekdaysFull[dt.weekday - 1]} ${dt.day} '
      '${_monthsFull[dt.month - 1]} à ${_hhmm(utc)}';
}

/// Nombre de jours / de puces par jour affichés dans le bloc `.slots` de la
/// carte résultat (maquette design-v2, #5357).
const _kSlotsPreviewDays = 3;
const _kSlotsPreviewPerDay = 3;

/// Construit l'aperçu « 3 jours de créneaux réels » d'une carte résultat
/// (#5357) à partir des créneaux réels du praticien. `null` quand le
/// praticien n'a aucun créneau disponible en ligne — la carte retombe alors
/// sur le bloc « aucun créneau en ligne » existant (#5358), jamais régressé.
List<ProviderResultDaySlots>? _buildDaySlots(
  List<Slot> slots,
  void Function(Slot) onSlotTap,
) {
  final available = slots.where((s) => s.isAvailable).toList();
  if (available.isEmpty) return null;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final byDay = <DateTime, List<Slot>>{};
  for (final slot in available) {
    // startsAt est UTC — grouper sur les composants bruts classerait un
    // créneau proche de minuit UTC sur le mauvais jour local.
    final local = slot.startsAt.toLocal();
    final key = DateTime(local.year, local.month, local.day);
    byDay.putIfAbsent(key, () => []).add(slot);
  }

  return List.generate(_kSlotsPreviewDays, (i) {
    final day = today.add(Duration(days: i));
    final daySlots = (byDay[day] ?? const <Slot>[]).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return ProviderResultDaySlots(
      dayLabel: _weekdays[day.weekday - 1],
      dateLabel: '${day.day} ${_monthsFull[day.month - 1]}',
      chips: [
        for (final slot in daySlots.take(_kSlotsPreviewPerDay))
          ProviderResultSlotChip(
            label: _hhmm(slot.startsAt),
            onTap: () => onSlotTap(slot),
          ),
      ],
    );
  });
}

// ---------------------------------------------------------------------------
// Search view : expérience MAP-CENTRIC (façon Waze/Google Maps)
//   • carte MapTiler plein écran + pins praticiens (clustering simple)
//   • barre de recherche flottante + chips de filtres rapides
//   • bottom sheet glissable listant les ProviderCard (snap 12/45/90 %)
//   • recherche langage naturel via POST /v1/search/parse (repli texte brut)
// ---------------------------------------------------------------------------

/// Filtre rapide (chip) : soit un terme de recherche plein texte (nom ou
/// spécialité), soit un filtre structuré de `SearchProvidersQuery`
/// (api/src/marketplace.rs). #6431 : « Téléconsult »/« Secteur 1 » n'ont pas
/// de représentation en texte libre (aucun praticien ne s'appelle
/// « téléconsultation » ni « secteur 1 ») — les envoyer via `q` vide
/// systématiquement la liste ; ils doivent porter les paramètres
/// `teleconsult`/`sector` correspondants.
class _QuickFilter {
  const _QuickFilter(this.key, this.label, this.icon,
      {this.query, this.teleconsult, this.sector});
  final String key;
  final String label;
  final IconData icon;
  final String? query;
  final bool? teleconsult;
  final String? sector;
}

const _quickFilters = <_QuickFilter>[
  _QuickFilter('dispo', 'Disponible', Icons.event_available_outlined,
      query: 'disponible'),
  _QuickFilter('teleconsult', 'Téléconsult', Icons.videocam_outlined,
      teleconsult: true),
  _QuickFilter('secteur1', 'Secteur 1', Icons.euro_outlined, sector: '1'),
  _QuickFilter('generaliste', 'Généraliste', Icons.medical_services_outlined,
      query: 'généraliste'),
  _QuickFilter('dentiste', 'Dentiste', Icons.masks_outlined,
      query: 'dentiste'),
];

/// Centre par défaut de la carte quand aucun praticien géolocalisé (Paris).
const _defaultCenter = LatLng(48.8566, 2.3522);

class _SearchView extends StatefulWidget {
  const _SearchView({
    required this.providers,
    required this.slotsByProvider,
    required this.loading,
    this.initialQuery,
  });
  final List<ProviderResult> providers;
  final Map<String, List<Slot>> slotsByProvider;
  final bool loading;
  final String? initialQuery;

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
  void initState() {
    super.initState();
    // #5269 : pré-remplit la barre visible avec le nom transmis par
    // « Reprendre RDV » (la recherche réseau correspondante est déjà lancée
    // par AppointmentsPage.initState).
    final initialQuery = widget.initialQuery;
    if (initialQuery != null && initialQuery.isNotEmpty) {
      _controller.text = initialQuery;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _mapController.dispose();
    super.dispose();
  }

  AppointmentsBloc get _bloc => context.read<AppointmentsBloc>();

  /// Recherche « propre » = texte libre + termes des chips actives à
  /// représentation texte (#6431 : les chips à filtre structuré, ex.
  /// « Téléconsult »/« Secteur 1 », n'y contribuent pas — voir
  /// [_activeTeleconsult]/[_activeSector]).
  String _composedQuery([String? overrideText]) {
    final parts = <String>[(overrideText ?? _controller.text).trim()];
    for (final f in _quickFilters) {
      if (_activeFilters.contains(f.key) && f.query != null) {
        parts.add(f.query!);
      }
    }
    return parts.where((p) => p.isNotEmpty).join(' ').trim();
  }

  /// #6431 : filtre structuré `teleconsult` porté par une chip active.
  bool? get _activeTeleconsult => _quickFilters.any(
        (f) => _activeFilters.contains(f.key) && f.teleconsult == true,
      )
          ? true
          : null;

  /// #6431 : filtre structuré `sector` porté par une chip active.
  String? get _activeSector {
    for (final f in _quickFilters) {
      if (_activeFilters.contains(f.key) && f.sector != null) return f.sector;
    }
    return null;
  }

  /// Frappe au clavier : recherche live débattue sur le texte + chips actifs.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _bloc.add(AppointmentsSearchChanged(
        _composedQuery(value),
        teleconsult: _activeTeleconsult,
        sector: _activeSector,
      ));
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
      _bloc.add(AppointmentsSearchChanged(
        raw,
        teleconsult: _activeTeleconsult,
        sector: _activeSector,
      ));
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
        _bloc.add(AppointmentsSearchChanged(
          raw,
          teleconsult: _activeTeleconsult,
          sector: _activeSector,
        ));
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
        _bloc.add(AppointmentsSearchChanged(
          effective,
          teleconsult: _activeTeleconsult,
          sector: _activeSector,
        ));
      },
    );
  }

  void _toggleFilter(_QuickFilter filter) {
    setState(() {
      if (!_activeFilters.remove(filter.key)) _activeFilters.add(filter.key);
    });
    _debounce?.cancel();
    _bloc.add(AppointmentsSearchChanged(
      _composedQuery(),
      teleconsult: _activeTeleconsult,
      sector: _activeSector,
    ));
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

  /// #5357 : un clic sur une puce créneau du bloc `.slots` de la carte
  /// résultat démarre directement la réservation — pas de détour par le
  /// sheet de détail, l'agenda du praticien se charge avec ce créneau
  /// automatiquement sélectionné.
  void _onSlotTap(ProviderResult provider, Slot slot) {
    _bloc.add(
      AppointmentsProviderSelected(provider, preselectSlotId: slot.id),
    );
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
          slotsByProvider: widget.slotsByProvider,
          loading: widget.loading,
          onCardTap: _onProviderFocused,
          onViewProfile: _openProviderProfile,
          onSlotTap: _onSlotTap,
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
    required this.slotsByProvider,
    required this.loading,
    required this.onCardTap,
    required this.onViewProfile,
    required this.onSlotTap,
  });

  final List<ProviderResult> providers;
  final Map<String, List<Slot>> slotsByProvider;
  final bool loading;
  final void Function(ProviderResult) onCardTap;
  final void Function(ProviderResult) onViewProfile;
  final void Function(ProviderResult, Slot) onSlotTap;

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
                  slotsByProvider: slotsByProvider,
                  loading: loading,
                  scrollController: scrollController,
                  onCardTap: onCardTap,
                  onViewProfile: onViewProfile,
                  onSlotTap: onSlotTap,
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
    required this.slotsByProvider,
    required this.loading,
    required this.scrollController,
    required this.onCardTap,
    required this.onViewProfile,
    required this.onSlotTap,
  });

  final List<ProviderResult> providers;
  final Map<String, List<Slot>> slotsByProvider;
  final bool loading;
  final ScrollController scrollController;
  final void Function(ProviderResult) onCardTap;
  final void Function(ProviderResult) onViewProfile;
  final void Function(ProviderResult, Slot) onSlotTap;

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
        // #5357 : 3 jours de créneaux réels par carte résultat — le
        // patient compare des disponibilités, pas des noms.
        final daySlots = _buildDaySlots(
          slotsByProvider[provider.id] ?? const <Slot>[],
          (slot) => onSlotTap(provider, slot),
        );
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
          daySlots: daySlots,
          onViewMoreSlots: daySlots == null ? null : () => onCardTap(provider),
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
  const _SlotsView({required this.state, required this.onContinue});
  final AppointmentsSlotsLoaded state;
  // #5336 : ouvre la feuille de confirmation — déclenché par `_ContinueBar`,
  // affichée sous la grille une fois un créneau sélectionné.
  final VoidCallback onContinue;

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
          return _SlotsMobileView(
            state: state,
            borderColor: borderColor,
            onContinue: onContinue,
          );
        },
      );
    }
    return _SlotsMobileView(
      state: state,
      borderColor: borderColor,
      onContinue: onContinue,
    );
  }
}

/// En-tête praticien (retour + avatar + identité) partagé entre l'agenda
/// chargé ([_SlotsMobileView]) et son squelette de chargement
/// ([_SlotsLoadingView]) : #5342, ne dépend que de [ProviderResult], monté
/// immédiatement même avant que les créneaux n'arrivent.
class _ProviderHeaderRow extends StatelessWidget {
  const _ProviderHeaderRow({required this.provider});
  final ProviderResult provider;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            initials: _initialsOf(provider.displayName),
            radius: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  provider.displayName,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                // #3825 : pas de ligne (ni espace résiduel) quand la
                // spécialité est vide.
                if (provider.specialty.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    provider.specialty,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                _ProviderMetaRow(provider: provider),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rangée méta (distance · secteur · tiers payant) sous l'identité de l'en-tête
/// praticien — reprend des données déjà portées par [ProviderResult] et
/// jusqu'ici affichées uniquement dans la recherche (maquette design-v2,
/// écran réservation, #5340). N'affiche que les items dont la donnée existe.
class _ProviderMetaRow extends StatelessWidget {
  const _ProviderMetaRow({required this.provider});
  final ProviderResult provider;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    if (provider.distanceKm != null) {
      final distance = '${provider.distanceKm!.toStringAsFixed(1)} km';
      items.add(_MetaItem(
        icon: Icons.place,
        label: provider.address != null
            ? '$distance · ${provider.address}'
            : distance,
      ));
    }
    if (provider.sector != null) {
      items.add(
        _MetaItem(icon: Icons.euro, label: 'Secteur ${provider.sector}'),
      );
    }
    if (provider.tiersPayant == true) {
      items.add(const _MetaItem(icon: Icons.credit_card, label: 'Tiers payant'));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 14, runSpacing: 4, children: items),
    );
  }
}

/// Un item `.mtx` de la rangée méta : icône `n400` 15px + libellé 12.5/`n600`.
class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: NubiaColors.n400),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: NubiaColors.n600),
        ),
      ],
    );
  }
}

/// Liste mobile historique : en-tête praticien + créneaux groupés par jour.
///
/// #5337 : la sélection d'un créneau n'y remplace plus rien — le formulaire
/// de confirmation est présenté à part, en `NubiaBottomSheet` modal (voir
/// `_AppointmentsPageState._openBookingSheet`), pour que cette grille reste
/// montée et de hauteur stable derrière la feuille. #5336 : la feuille ne
/// s'ouvre plus automatiquement — la sélection affiche d'abord la barre
/// collante `_ContinueBar`, qui l'ouvre au tap de « Continuer ».
class _SlotsMobileView extends StatelessWidget {
  const _SlotsMobileView({
    required this.state,
    required this.borderColor,
    required this.onContinue,
  });
  final AppointmentsSlotsLoaded state;
  final Color borderColor;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final selectedSlot = state.selectedSlot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProviderHeaderRow(provider: state.provider),
        Divider(height: 1, color: borderColor),
        Expanded(
          child: state.slots.isEmpty
              ? const NubiaEmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'Aucun créneau disponible.',
                  subtitle:
                      'Revenez plus tard ou choisissez un autre praticien.',
                )
              : _SlotsByDay(state: state),
        ),
        if (selectedSlot != null)
          _ContinueBar(slot: selectedSlot, onContinue: onContinue),
      ],
    );
  }
}

/// Barre collante « Continuer » (maquette design-v2 patient-re-servation,
/// bloc `.bar`, #5336) : affichée sous la grille de créneaux dès qu'un
/// créneau est sélectionné, au lieu d'ouvrir directement le panneau motif —
/// « Continuer » ouvre la feuille de confirmation (`_BookingPanel`, #5337).
/// N'émet aucun événement bloc : la sélection courante et le `holdToken`
/// restent intacts.
class _ContinueBar extends StatelessWidget {
  const _ContinueBar({required this.slot, required this.onContinue});
  final Slot slot;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final durationMin =
        slot.duration.inMinutes > 0 ? slot.duration.inMinutes : 30;
    return Container(
      key: const Key('slots_continue_bar'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
      decoration: const BoxDecoration(
        color: NubiaColors.n0,
        border: Border(top: BorderSide(color: NubiaColors.n200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _continueBarDateLabel(slot.startsAt),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Durée estimée $durationMin min',
                  style: const TextStyle(fontSize: 12, color: NubiaColors.n500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          NubiaButton(
            key: const Key('slots_continue_button'),
            label: 'Continuer',
            icon: Icons.arrow_forward,
            size: NubiaButtonSize.lg,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}

/// #5342 : squelette de `AppointmentsSlotsLoading` — l'en-tête praticien
/// reste monté immédiatement (déjà porté par l'état), seule la zone
/// créneaux affiche un placeholder animé, façon DS. Remplace l'ancien
/// `CircularProgressIndicator` centré (écran blanc au moment le plus
/// anxiogène de la maquette).
class _SlotsLoadingView extends StatelessWidget {
  const _SlotsLoadingView({required this.provider});
  final ProviderResult provider;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final borderColor = tokens?.borderSubtle ?? Theme.of(context).dividerColor;
    return Column(
      key: const Key('slots_loading_skeleton'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProviderHeaderRow(provider: provider),
        Divider(height: 1, color: borderColor),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              const NubiaSkeletonLoader(width: 120, height: 18),
              const SizedBox(height: 12),
              _skeletonSlotWrap(),
              const SizedBox(height: 24),
              const NubiaSkeletonLoader(width: 120, height: 18),
              const SizedBox(height: 12),
              _skeletonSlotWrap(),
            ],
          ),
        ),
      ],
    );
  }

  /// Grille de puces créneaux en squelette, mêmes dimensions qu'un
  /// [SlotChip] (36 px de haut, 56 px de large min.) pour que l'écran ne
  /// « saute » pas visuellement une fois les vrais créneaux chargés.
  Widget _skeletonSlotWrap() {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        NubiaSkeletonLoader(width: 56, height: 36, borderRadius: 8),
        NubiaSkeletonLoader(width: 56, height: 36, borderRadius: 8),
        NubiaSkeletonLoader(width: 56, height: 36, borderRadius: 8),
        NubiaSkeletonLoader(width: 56, height: 36, borderRadius: 8),
        NubiaSkeletonLoader(width: 56, height: 36, borderRadius: 8),
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

/// Regroupement par jour en préservant l'ordre chronologique d'origine.
///
/// #5366 : startsAt est UTC (isUtc == true) — grouper sur les composants
/// bruts classait un créneau proche de minuit UTC sur le mauvais jour local
/// (ex : 23h30 UTC = 01h30 Paris le lendemain). Partagé entre la liste par
/// jour et le rail de jours (#5339) pour garantir le même découpage.
Map<DateTime, List<Slot>> _groupSlotsByLocalDay(List<Slot> slots) {
  final groups = <DateTime, List<Slot>>{};
  for (final slot in slots) {
    final localStartsAt = slot.startsAt.toLocal();
    final key = DateTime(
      localStartsAt.year,
      localStartsAt.month,
      localStartsAt.day,
    );
    groups.putIfAbsent(key, () => []).add(slot);
  }
  return groups;
}

/// Rail de jours + liste des créneaux groupés par jour, chaque jour = titre
/// + [SlotChip] (maquette design-v2 patient-re-servation, point 4, #5339) :
/// le rail donne « la carte du territoire d'un coup d'œil » (nb de créneaux
/// par jour, jours pleins grisés) et permet de sauter directement à un jour
/// avant de scroller la liste en dessous.
class _SlotsByDay extends StatefulWidget {
  const _SlotsByDay({required this.state});
  final AppointmentsSlotsLoaded state;

  @override
  State<_SlotsByDay> createState() => _SlotsByDayState();
}

class _SlotsByDayState extends State<_SlotsByDay> {
  DateTime? _selectedDay;
  final _dayHeaderKeys = <DateTime, GlobalKey>{};

  void _onDayTap(DateTime day) {
    setState(() => _selectedDay = day);
    final keyContext = _dayHeaderKeys[day]?.currentContext;
    if (keyContext != null) {
      Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupSlotsByLocalDay(widget.state.slots);
    _dayHeaderKeys.removeWhere((day, _) => !groups.containsKey(day));
    for (final day in groups.keys) {
      _dayHeaderKeys.putIfAbsent(day, () => GlobalKey());
    }
    final activeDay =
        _selectedDay != null && groups.containsKey(_selectedDay)
            ? _selectedDay!
            : groups.keys.first;

    return Column(
      children: [
        _DayRail(groups: groups, activeDay: activeDay, onDayTap: _onDayTap),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  key: _dayHeaderKeys[entry.key],
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _dayHeader(entry.key),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                // Sous-groupes matin / après-midi (affichés seulement si non
                // vides) pour scanner encore plus vite, façon Doctolib.
                ..._buildPeriods(context, entry.value),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
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

  /// Grille à 4 colonnes fixes de [SlotChip] conservant l'état de sélection
  /// courant (design-v2, #5341) : cellules de 44 px de haut (cible tactile),
  /// alignées, sans contournement de largeur intrinsèque.
  Widget _slotWrap(BuildContext context, List<Slot> slots) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: slots.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisExtent: 44,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final slot = slots[index];
        return SlotChip(
          // Maquette web (#5365) : puce indisponible = contenu « — »,
          // pas l'heure barrée.
          label: slot.isAvailable ? _hhmm(slot.startsAt) : '—',
          state: !slot.isAvailable
              ? SlotChipState.unavailable
              : widget.state.selectedSlot?.id == slot.id
                  ? SlotChipState.selected
                  : SlotChipState.available,
          onTap: slot.isAvailable
              ? () => context
                  .read<AppointmentsBloc>()
                  .add(AppointmentsSlotSelected(slot))
              : null,
        );
      },
    );
  }
}

/// Bandeau `.days` de la maquette : un jour par cellule, espacées de 8px,
/// chacune `flex:1`. Fond `n0`, bordure basse `n200`.
class _DayRail extends StatelessWidget {
  const _DayRail({
    required this.groups,
    required this.activeDay,
    required this.onDayTap,
  });

  final Map<DateTime, List<Slot>> groups;
  final DateTime activeDay;
  final void Function(DateTime day) onDayTap;

  @override
  Widget build(BuildContext context) {
    final days = groups.keys.toList();
    return Container(
      key: const Key('day_rail'),
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
      decoration: const BoxDecoration(
        color: NubiaColors.n0,
        border: Border(bottom: BorderSide(color: NubiaColors.n200)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _DayCell(
                day: days[i],
                availableCount:
                    groups[days[i]]!.where((s) => s.isAvailable).length,
                isActive: days[i] == activeDay,
                onTap: onDayTap,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Cellule `.dy` du rail : abrégé jour + quantième (Fraunces) + compteur de
/// dispo. `.dy.on` = fond `brand700`/texte blanc ; `.dy.off` (0 dispo) =
/// quantième `n300`, compteur « — » non gras, non sélectionnable.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.availableCount,
    required this.isActive,
    required this.onTap,
  });

  final DateTime day;
  final int availableCount;
  final bool isActive;
  final void Function(DateTime day) onTap;

  bool get _isOff => availableCount == 0;

  @override
  Widget build(BuildContext context) {
    final on = isActive && !_isOff;
    return GestureDetector(
      onTap: _isOff ? null : () => onTap(day),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: on ? NubiaColors.brand700 : NubiaColors.n0,
          border: Border.all(color: NubiaColors.n200),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _weekdays[day.weekday - 1].replaceAll('.', '').toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: on ? NubiaColors.n0 : NubiaColors.n400,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${day.day}',
              style: GoogleFonts.fraunces(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: on
                    ? NubiaColors.n0
                    : _isOff
                        ? NubiaColors.n300
                        : NubiaColors.n900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _isOff ? '—' : '$availableCount dispo',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: _isOff ? FontWeight.w400 : FontWeight.w600,
                color: on
                    ? NubiaColors.n0.withValues(alpha: 0.8)
                    : _isOff
                        ? NubiaColors.n400
                        : NubiaColors.brand700,
              ),
            ),
          ],
        ),
      ),
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

/// #5343 : pendant l'appel `POST /v1/bookings` (état `AppointmentsBookingLoading`),
/// le récap (créneau + motif) reste visible sous un overlay de progression —
/// remplace l'ancien `Center(CircularProgressIndicator())` qui affichait un
/// écran blanc. Le formulaire (et son bouton de confirmation) n'est pas
/// remonté ici : pas de risque de double soumission pendant la progression.
class _BookingProgressView extends StatelessWidget {
  const _BookingProgressView({required this.state});
  final AppointmentsBookingLoading state;

  @override
  Widget build(BuildContext context) {
    final slot = state.selectedSlot;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: NubiaCard(
            key: const Key('booking_progress_recap_card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    NubiaAvatar(
                      initials: _initialsOf(state.provider.displayName),
                      radius: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.provider.displayName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${_dayHeader(slot.startsAt)} à ${_hhmm(slot.startsAt)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (state.motif.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    state.motif,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Overlay de progression (maquette design-v2, point 6 : « la
        // confirmation garde le récap sous un overlay de progression »).
        // Même opacité de scrim que NubiaBottomSheet (45 %).
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.45),
            child: const Center(
              child: CircularProgressIndicator(
                key: Key('booking_progress_indicator'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Carte récap du créneau choisi (maquette design-v2 patient-re-servation,
/// bloc `.recap`) : jour/heure, praticien, durée + lien « Modifier » qui
/// referme la feuille de confirmation modale (`NubiaBottomSheet`, #5337) pour
/// révéler la grille de créneaux restée stable derrière. N'émet aucun
/// événement bloc : la sélection courante et le `holdToken` restent intacts,
/// [onModifier] ne fait que dépiler la feuille.
class _SlotRecapCard extends StatelessWidget {
  const _SlotRecapCard({required this.state, this.onModifier});
  final AppointmentsSlotsLoaded state;
  final VoidCallback? onModifier;

  @override
  Widget build(BuildContext context) {
    final slot = state.selectedSlot!;
    final startsAt = slot.startsAt.toLocal();
    final durationMin =
        slot.duration.inMinutes > 0 ? slot.duration.inMinutes : 30;
    return Container(
      key: const Key('booking_slot_recap_card'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: NubiaColors.brand50,
        border: Border.all(color: NubiaColors.brand100),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NubiaColors.brand700,
              borderRadius: BorderRadius.circular(12),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _weekdays[startsAt.weekday - 1]
                        .replaceAll('.', '')
                        .toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: NubiaColors.n0.withValues(alpha: 0.8),
                    ),
                  ),
                  Text(
                    '${startsAt.day}',
                    style: GoogleFonts.fraunces(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: NubiaColors.n0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _slotRecapDateLabel(slot.startsAt),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${state.provider.displayName} · $durationMin min',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: NubiaColors.brand800.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          if (onModifier != null) ...[
            const SizedBox(width: 8),
            InkWell(
              key: const Key('booking_slot_recap_modify'),
              onTap: onModifier,
              child: const Text(
                'Modifier',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: NubiaColors.brand700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Formulaire de confirmation (étape 3 « Vos informations » du tunnel,
/// maquette design-v2 patient-web-tunnel-reservation) : présenté en
/// `NubiaBottomSheet` modal une fois une puce sélectionnée, au-dessus de la
/// grille de créneaux restée stable (#5337). Pour un visiteur anonyme, ce
/// même formulaire crée le compte à la confirmation — jamais avant — dans
/// le même geste que la réservation (#5362).
class _BookingPanel extends StatefulWidget {
  const _BookingPanel({required this.state, this.onModifier});
  final AppointmentsSlotsLoaded state;
  // #5338 : referme la feuille de confirmation et rouvre la grille de
  // créneaux — la sélection (`state.selectedSlot`) et le `holdToken` ne sont
  // pas touchés, `null` si l'appelant ne fournit pas de grille à rouvrir.
  final VoidCallback? onModifier;

  @override
  State<_BookingPanel> createState() => _BookingPanelState();
}

/// #5335 : puces de motif tapables au-dessus du champ « Motif de
/// consultation », dans l'ordre exact demandé par la maquette design-v2.
const List<String> _motifSuggestions = [
  'Contrôle',
  'Douleur',
  'Détartrage',
  'Urgence',
  'Suivi de traitement',
];

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
  // #5659 : dépendants du patient connecté, pour le sélecteur « Pour qui est
  // ce rendez-vous ? » — chargés une fois si une session existe (un visiteur
  // anonyme n'a pas encore de dépendants, cf. `needsAccount`).
  List<Dependent> _dependents = const [];
  // `null` = réservation pour le compte connecté lui-même ; sinon `id` du
  // dépendant sélectionné, envoyé tel quel comme `on_behalf_of`.
  String? _selectedBeneficiaryId;

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
    if (context.read<AuthCubit>().state is AuthAuthenticated) {
      unawaited(_loadDependents());
    }
  }

  Future<void> _loadDependents() async {
    final gi = GetIt.instance;
    if (!gi.isRegistered<ListDependentsUseCase>()) return;
    final result = await gi<ListDependentsUseCase>().call();
    if (!mounted) return;
    result.fold(
      (_) {},
      (dependents) => setState(() => _dependents = dependents),
    );
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

    // #5337 : ce panneau vit désormais toujours dans un `NubiaBottomSheet`
    // (fond, radius, padding 16 déjà fournis par le DS) — plus de conteneur
    // ni de padding propres ici, qui doublaient ceux de la feuille et
    // provoquaient un débordement horizontal du contenu.
    return SingleChildScrollView(
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
            // #5659 : sélecteur de bénéficiaire — un patient déjà connecté
            // ayant des dépendants actifs peut réserver pour lui-même ou pour
            // l'un d'eux (`on_behalf_of`, tutelle vérifiée côté API).
            if (!needsAccount && _dependents.isNotEmpty) ...[
              Text('Pour qui est ce rendez-vous ?', style: sectionTitle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  NubiaChip(
                    key: const Key('booking_beneficiary_self'),
                    label: 'Moi',
                    variant: NubiaChipVariant.choice,
                    selected: _selectedBeneficiaryId == null,
                    onTap: () => setState(() => _selectedBeneficiaryId = null),
                  ),
                  for (final dependent in _dependents)
                    NubiaChip(
                      key: Key('booking_beneficiary_${dependent.id}'),
                      label: dependent.displayName,
                      variant: NubiaChipVariant.choice,
                      selected: _selectedBeneficiaryId == dependent.id,
                      onTap: () => setState(
                          () => _selectedBeneficiaryId = dependent.id),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            _SlotRecapCard(state: state, onModifier: widget.onModifier),
            const SizedBox(height: 20),
            Text('Motif de la consultation', style: sectionTitle),
            const SizedBox(height: 8),
            // #5335 : taper une puce remplit le champ et rend le clavier
            // optionnel — même événement `AppointmentsMotifChanged` que la
            // saisie libre ci-dessous.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in _motifSuggestions)
                  NubiaChip(
                    key: Key('booking_motif_chip_$suggestion'),
                    label: suggestion,
                    variant: NubiaChipVariant.choice,
                    selected: state.motif.trim() == suggestion,
                    onTap: () {
                      context
                          .read<AppointmentsBloc>()
                          .add(AppointmentsMotifChanged(suggestion));
                      setState(() => _motif.text = suggestion);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
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
                            onBehalfOf: _selectedBeneficiaryId,
                          ),
                        ),
              ),
            ),
            const SizedBox(height: 8),
            // #5344 : réassurance verbatim maquette (`.reass`), annonce
            // AVANT le tap que la demande devra être confirmée par le
            // cabinet (statut réel après POST /v1/bookings).
            SizedBox(
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_user,
                    size: 14,
                    color: tokens?.successFg ?? NubiaColors.successFg,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Sans engagement — le cabinet confirme sous 24 h',
                    style: subdued?.copyWith(
                      fontSize: 12,
                      color: NubiaColors.n500,
                    ),
                  ),
                ],
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
