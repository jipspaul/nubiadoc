import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'config.dart';

/// Shared scaffold for the professional apps (praticien + secrétariat).
///
/// Desktop (width ≥ 720 px): [NavigationRail] on the left + content area on
/// the right.  Mobile: [Drawer] with a hamburger [AppBar].
///
/// Destinations flagged with [ProNavDestination.requiresClinical] are
/// automatically hidden when [session.canAccessClinical] is false, ensuring
/// the secretariat app never exposes clinical surfaces.
class ProShell extends StatefulWidget {
  const ProShell({
    super.key,
    required this.config,
    required this.session,
    this.bodyBuilder,
    this.trailingActions = const [],
    this.onSignOut,
    this.currentRoute,
    this.onNavigate,
    this.searchHint,
    this.onSearchTap,
  });

  final ProConfig config;
  final AuthSession session;

  /// Provides the main content widget for the selected destination.
  /// Defaults to a labelled [NubiaEmptyState] placeholder when omitted.
  final Widget Function(BuildContext context, ProNavDestination destination)?
      bodyBuilder;

  /// Extra icon-buttons rendered above the sign-out button in the rail /
  /// drawer (e.g. a demo shortcut).
  final List<Widget> trailingActions;

  final VoidCallback? onSignOut;

  /// Current go_router location (e.g. `state.uri.path`), used to select the
  /// destination whose [ProNavDestination.route] matches on build AND on
  /// every rebuild (direct navigation, reload, browser back/forward).
  ///
  /// When omitted, [ProShell] falls back to its own local `_index` state
  /// (legacy behaviour, kept for callers that don't route destinations
  /// individually).
  final String? currentRoute;

  /// Called when the user picks a destination in the rail/drawer. When
  /// provided, [ProShell] delegates navigation to the caller (typically
  /// `context.go(destination.route)`) instead of only updating its local
  /// state — this is what keeps the URL in sync with the selected tab.
  final void Function(ProNavDestination destination)? onNavigate;

  /// Placeholder du point d'entrée de recherche globale affiché dans la
  /// barre de titre desktop (#5389, ex. « Patient, devis, commande… »).
  /// `null` (défaut) : aucune entrée de recherche n'est affichée —
  /// comportement inchangé pour les apps qui ne la fournissent pas encore.
  final String? searchHint;

  /// Appelé au clic sur l'entrée de recherche ou au raccourci ⌘K (#5389).
  /// Ignoré si [searchHint] est `null`.
  final VoidCallback? onSearchTap;

  @override
  State<ProShell> createState() => _ProShellState();
}

class _ProShellState extends State<ProShell> {
  int _index = 0;

  List<ProNavDestination> get _destinations => widget.config.destinations
      .where((d) => !d.requiresClinical || widget.session.canAccessClinical)
      .toList();

  /// Selects the destination that matches [widget.currentRoute] when the
  /// caller drives navigation from go_router; falls back to the local
  /// `_index` (updated by [onDestinationSelected]/[onTap]) otherwise. This
  /// keeps the selected tab in sync with the URL on first build AND on any
  /// rebuild triggered by a direct navigation, reload or browser
  /// back/forward — none of which go through `setState` locally.
  int _resolveIndex(List<ProNavDestination> destinations) {
    final route = widget.currentRoute;
    if (route != null) {
      final matched = destinations.indexWhere((d) => d.route == route);
      if (matched != -1) return matched;
    }
    return _index.clamp(0, destinations.length - 1);
  }

  void _select(List<ProNavDestination> destinations, int i) {
    final destination = destinations[i];
    if (widget.onNavigate != null) {
      widget.onNavigate!(destination);
    } else {
      setState(() => _index = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    final index = _resolveIndex(destinations);
    final current = destinations[index];

    final shell = LayoutBuilder(
      builder: (context, constraints) {
        return constraints.maxWidth >= 720
            ? _buildDesktop(context, destinations, index, current)
            : _buildMobile(context, destinations, index, current);
      },
    );

    final onSearchTap = widget.onSearchTap;
    if (onSearchTap == null) return shell;

    // #5389 — ⌘K ouvre la recherche globale depuis n'importe où dans le
    // shell (même pattern `CallbackShortcuts` que side_column.dart, #4941).
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            onSearchTap,
      },
      child: shell,
    );
  }

  Widget _content(BuildContext context, ProNavDestination destination) {
    if (widget.bodyBuilder != null) {
      return widget.bodyBuilder!(context, destination);
    }
    return Center(
      child: NubiaEmptyState(
        icon: Icons.construction_outlined,
        title: destination.label,
      ),
    );
  }

  Widget _trailing(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...widget.trailingActions,
        if (widget.onSignOut != null)
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: widget.onSignOut,
          ),
      ],
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    List<ProNavDestination> destinations,
    int index,
    ProNavDestination current,
  ) {
    // `NavigationRail` ne défile pas ses propres destinations : au-delà
    // d'un certain nombre d'entrées (ex. app_secretariat, #4153, 12
    // destinations), `NavigationRailLabelType.all` (icône + libellé empilés
    // par destination) déborde verticalement sur les écrans/viewports plus
    // petits. Bascule automatique en mode compact (libellé visible
    // uniquement pour l'entrée sélectionnée) au-delà du seuil — recommandé
    // par Flutter lui-même pour les rails à nombreuses destinations, aucune
    // action requise côté apps consommatrices.
    const maxDestinationsForFullLabels = 9;
    final labelType = destinations.length > maxDestinationsForFullLabels
        ? NavigationRailLabelType.selected
        : NavigationRailLabelType.all;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => _select(destinations, i),
            labelType: labelType,
            // Monogramme Nubia — le FlutterLogo par défaut faisait
            // « démo non finie » (#3363/#3375).
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  'N',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _trailing(context),
                ),
              ),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Scaffold(
              appBar: NubiaAppBar(
                title: current.label,
                centerTitle: false,
                actions: widget.searchHint != null && widget.onSearchTap != null
                    ? [
                        _SearchTrigger(
                          hint: widget.searchHint!,
                          onTap: widget.onSearchTap!,
                        ),
                      ]
                    : null,
              ),
              body: _content(context, current),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(
    BuildContext context,
    List<ProNavDestination> destinations,
    int index,
    ProNavDestination current,
  ) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.config.appTitle)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: Text(
                  widget.config.spaceLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Divider(),
              for (int i = 0; i < destinations.length; i++)
                ListTile(
                  leading: Icon(destinations[i].icon),
                  title: Text(destinations[i].label),
                  selected: i == index,
                  onTap: () {
                    Navigator.of(context).pop();
                    _select(destinations, i);
                  },
                ),
              const Spacer(),
              _trailing(context),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: _content(context, current),
    );
  }
}

/// Point d'entrée de la recherche globale dans la barre de titre desktop
/// (#5389, maquette design-v2 secrétariat) — encart bordé, loupe, placeholder
/// grisé et badge clavier ⌘K, même styles que `_GlobalSearchField`
/// (app_practicien, patient_identity_bar.dart, #4948).
class _SearchTrigger extends StatelessWidget {
  const _SearchTrigger({required this.hint, required this.onTap});

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('global_search_trigger'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 40,
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.borderDefault),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search, size: 18, color: tokens.textTertiary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    hint,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: tokens.textTertiary),
                  ),
                ),
                const SizedBox(width: 8),
                const _SearchShortcutBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge « ⌘K » (#5389) — même style que `_GlobalSearchShortcutBadge`
/// (app_practicien, patient_identity_bar.dart, #4948).
class _SearchShortcutBadge extends StatelessWidget {
  const _SearchShortcutBadge();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Text(
        '⌘K',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textTertiary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
