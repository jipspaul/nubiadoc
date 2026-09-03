import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'config.dart';
import 'notifications/pro_notifications_bell.dart';
import 'notifications/pro_notifications_cubit.dart';

/// Largeur fixe de la barre latérale desktop (#5138, maquette design-v2
/// secrétariat, colonne « Proposé ») — remplace le rail d'icônes à largeur
/// variable (56/256px selon [NavigationRailLabelType]).
const double _sidebarWidth = 250;

/// Couleur du texte/icône d'une entrée non sélectionnée (#5138, verbatim
/// maquette) — n'existe dans aucun token [NubiaColors]/[NubiaTokens] existant
/// (palette neutre chaude la plus proche, `n300`/`n400`, ne correspond pas).
const Color _sidebarText = Color(0xFFC4BFB9);

/// Couleur d'un intitulé de groupe (`.grpl`, #5138, verbatim maquette).
const Color _sidebarGroupLabel = Color(0xFF6B6660);

/// Fond d'une entrée sélectionnée : `rgba(255,255,255,.11)` (#5138, verbatim
/// maquette) — 0.11 × 255 ≈ 28 (0x1C) d'alpha sur blanc pur.
const Color _sidebarActiveBg = Color(0x1CFFFFFF);

/// Shared scaffold for the professional apps (praticien + secrétariat).
///
/// Desktop (width ≥ 720 px): a 250px labelled sidebar (#5138) on the left +
/// content area on the right.  Mobile: [Drawer] with a hamburger [AppBar].
///
/// Destinations flagged with [ProNavDestination.requiresClinical] are
/// automatically hidden when [session.canAccessClinical] is false, ensuring
/// the secretariat app never exposes clinical surfaces.
class ProShell extends StatefulWidget {
  const ProShell({
    super.key,
    required this.config,
    required this.session,
    this.body,
    this.bodyBuilder,
    this.trailingActions = const [],
    this.onSignOut,
    this.currentRoute,
    this.onNavigate,
    this.searchHint,
    this.onSearchTap,
    this.notificationRepository,
    this.notificationEvents,
    this.onNotificationTap,
  });

  final ProConfig config;
  final AuthSession session;

  /// Content rendered directly, taking priority over [bodyBuilder]. Intended
  /// for callers wiring a `StatefulShellRoute` (see [ProNavDestination.route]
  /// doc): go_router already resolves the active destination's widget, so
  /// [ProShell] only owns the rail/drawer — it skips its own content
  /// [Scaffold]/`AppBar` on desktop so the routed page's chrome (if any)
  /// isn't duplicated. `null` (default) : legacy [bodyBuilder] behaviour,
  /// unchanged for callers that don't route destinations individually.
  final Widget? body;

  /// Provides the main content widget for the selected destination.
  /// Defaults to a labelled [NubiaEmptyState] placeholder when omitted.
  /// Ignored when [body] is provided.
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

  /// Alimente la cloche de notifications de la topbar (#6263, badge non-lus
  /// + panneau liste, `GET /v1/notifications`). `null` (défaut) : aucune
  /// cloche affichée — comportement inchangé pour les apps/tests qui ne la
  /// fournissent pas (voir aussi [searchHint]).
  final NotificationRepository? notificationRepository;

  /// Flux temps réel des notifications (canal WS `notifications`) — optionnel :
  /// sans lui la cloche reste sur son polling 60 s (#6263). Avec lui : badge
  /// instantané + bandeau SnackBar à chaque notification reçue.
  final NotificationEventsPort? notificationEvents;

  /// Appelé au clic sur une notification du panneau (#6264, deep-link
  /// kind→route) — la notification vient d'être marquée lue. `ProShell` ne
  /// connaît ni le kind→route mapping ni le routeur de l'app appelante
  /// (chacun des 3 apps pro a son propre `AppRouter`/`NotificationRouteResolver`) :
  /// c'est à l'appelant de résoudre la route et de naviguer (typiquement
  /// `Navigator.of(context).pop()` pour refermer le panneau puis
  /// `context.go(route)`). `null` (défaut) : aucune navigation, comportement
  /// inchangé pour les apps/tests qui ne le fournissent pas encore.
  final void Function(BuildContext context, AppNotification notification)?
      onNotificationTap;

  @override
  State<ProShell> createState() => _ProShellState();
}

/// One row of the flattened rail/drawer list (#5139) : either a navigable
/// [destination], or a collapsible group [header] — both occupy one index so
/// they share the rail's/drawer's tap handling ([_ProShellState._selectRow]
/// tells them apart via [group]).
class _NavRow {
  const _NavRow.destination(this.destination)
      : group = null,
        collapsed = false;

  const _NavRow.header(this.group, this.collapsed) : destination = null;

  final ProNavDestination? destination;
  final String? group;
  final bool collapsed;
}

class _ProShellState extends State<ProShell> with WidgetsBindingObserver {
  int _index = 0;
  late final Set<String> _collapsedGroups = {...widget.config.collapsedGroups};

  /// `null` quand [ProShell.notificationRepository] n'est pas fourni (#6263)
  /// — pas de cloche dans ce cas (voir [ProShell.notificationRepository]).
  ProNotificationsCubit? _notificationsCubit;

  @override
  void initState() {
    super.initState();
    final repository = widget.notificationRepository;
    if (repository != null) {
      _notificationsCubit = ProNotificationsCubit(
        repository: repository,
        events: widget.notificationEvents,
      );
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void dispose() {
    if (_notificationsCubit != null) {
      WidgetsBinding.instance.removeObserver(this);
      _notificationsCubit!.close();
    }
    super.dispose();
  }

  /// Rafraîchit le badge non-lus au retour au premier plan (#6263, ex.
  /// bascule d'onglet/fenêtre puis retour) — en complément du polling 60s.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _notificationsCubit?.refreshUnreadCount();
    }
  }

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

  /// [_collapsedGroups], sauf le groupe de [current] (#5139) — la nav ne
  /// doit jamais masquer la destination actuellement affichée, même si son
  /// groupe est replié par défaut ou a été replié manuellement.
  Set<String> _effectiveCollapsedGroups(ProNavDestination current) {
    final group = current.group;
    if (group == null || !_collapsedGroups.contains(group)) {
      return _collapsedGroups;
    }
    return {..._collapsedGroups}..remove(group);
  }

  /// Aplatit [destinations] en lignes de rail/drawer (#5139) : une ligne
  /// d'en-tête cliquable par groupe — toujours visible, même repliée —
  /// suivie de ses destinations, omises tant que le groupe appartient à
  /// [collapsedGroups].
  List<_NavRow> _buildRows(
    List<ProNavDestination> destinations,
    Set<String> collapsedGroups,
  ) {
    final rows = <_NavRow>[];
    String? lastGroup;
    for (final d in destinations) {
      if (d.group != lastGroup) {
        lastGroup = d.group;
        if (d.group != null) {
          rows.add(_NavRow.header(d.group!, collapsedGroups.contains(d.group)));
        }
      }
      if (d.group == null || !collapsedGroups.contains(d.group)) {
        rows.add(_NavRow.destination(d));
      }
    }
    return rows;
  }

  void _selectRow(
      List<ProNavDestination> destinations, List<_NavRow> rows, int i) {
    final row = rows[i];
    final group = row.group;
    if (group != null) {
      setState(() {
        if (_collapsedGroups.contains(group)) {
          _collapsedGroups.remove(group);
        } else {
          _collapsedGroups.add(group);
        }
      });
      return;
    }
    final destination = row.destination!;
    if (widget.onNavigate != null) {
      widget.onNavigate!(destination);
    } else {
      setState(() => _index = destinations.indexOf(destination));
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    final index = _resolveIndex(destinations);
    final current = destinations[index];
    final rows = _buildRows(destinations, _effectiveCollapsedGroups(current));
    final rowIndex = rows.indexWhere((r) => r.destination == current);

    final shell = LayoutBuilder(
      builder: (context, constraints) {
        return constraints.maxWidth >= 720
            ? _buildDesktop(context, destinations, rows, rowIndex, current)
            : _buildMobile(context, destinations, rows, rowIndex, current);
      },
    );

    final onSearchTap = widget.onSearchTap;
    if (onSearchTap == null) return shell;

    // #5389/#6311 — ⌘K (macOS) ou Ctrl+K (Windows/Linux, les 3 apps pro sont
    // des back-offices « PC ») ouvre la recherche globale depuis n'importe où
    // dans le shell (même pattern `CallbackShortcuts` que side_column.dart,
    // #4941).
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): onSearchTap,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
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

  /// Icône de destination surmontée d'un badge compteur (#5387) quand
  /// [ProNavDestination.badgeCount] est renseigné et non nul — même icône
  /// nue sinon (pas de pastille vide). Couleur sémantique selon
  /// [ProNavDestination.badgeColor] : vert (`--brand600`, personnes
  /// présentes / non lus) ou ambre (`--warnFg`, à traiter avant échéance),
  /// conformément à la maquette « Architecture de navigation » (#5142).
  Widget _iconWithBadge(BuildContext context, ProNavDestination destination) {
    final count = destination.badgeCount;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final badgeColor = switch (destination.badgeColor) {
      ProNavBadgeColor.brand => NubiaColors.brand600,
      ProNavBadgeColor.warning => tokens.warningFg,
    };
    return Badge(
      label: Text('$count'),
      isLabelVisible: count != null && count > 0,
      backgroundColor: badgeColor,
      textColor: Colors.white,
      child: Icon(destination.icon),
    );
  }

  /// Chevron d'en-tête de groupe (#5139, maquette design-v2 secrétariat) :
  /// `chevron_right` replié, `expand_more` déplié — 13px. [color] par défaut
  /// tertiaire du thème (drawer mobile clair) ; la barre latérale sombre
  /// (#5138) passe explicitement [_sidebarGroupLabel].
  Widget _groupHeaderIcon(BuildContext context, bool collapsed,
      {Color? color}) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Icon(
      collapsed ? Icons.chevron_right : Icons.expand_more,
      size: 13,
      color: color ?? tokens.textTertiary,
    );
  }

  /// En-tête de groupe repliable de la barre latérale desktop (#5138,
  /// verbatim maquette `.grpl`) — 9.5px/700, letter-spacing .8px,
  /// `_sidebarGroupLabel`. Casse d'origine conservée (pas de
  /// `.toUpperCase()`) : Flutter n'a pas d'équivalent à `text-transform`
  /// CSS qui laisserait la donnée intacte, et `row.group` est le texte
  /// exact recherché par les tests existants (#5139). Le tap (toute la
  /// ligne) est intercepté par [_selectRow] pour replier/déplier au lieu de
  /// naviguer.
  ///
  /// [Semantics] explicite (#6192) : la sémantique auto-générée d'`InkWell`
  /// ne remonte pas jusqu'à l'arbre d'accessibilité une fois imbriquée dans
  /// le `ListView` scrollable de la barre latérale (`_buildDesktop`) — un
  /// lecteur d'écran ne voyait aucun des en-têtes de groupe malgré un rendu
  /// et un clic fonctionnels.
  Widget _sidebarGroupHeader(
    BuildContext context,
    _NavRow row, {
    required VoidCallback onTap,
  }) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: row.group!,
      expanded: !row.collapsed,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
            child: Row(
              children: [
                _groupHeaderIcon(context, row.collapsed,
                    color: _sidebarGroupLabel),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    row.group!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: _sidebarGroupLabel,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Entrée de la barre latérale desktop (#5138, verbatim maquette `.nv`) :
  /// hauteur 32px, radius 8px, icône 18px + libellé 13px/500. Sélectionnée
  /// (`.on`) : fond `rgba(255,255,255,.11)`, texte blanc, icône remplie
  /// (FILL 1 — sans effet visuel tant que la police d'icônes du projet
  /// (`MaterialIcons`, glyphes fixes) ne supporte pas l'axe variable `fill`,
  /// mais correct et prêt pour une police d'icônes variable future).
  ///
  /// [Semantics] explicite (#6192) : la sémantique auto-générée d'`InkWell`
  /// ne remonte pas jusqu'à l'arbre d'accessibilité une fois imbriquée dans
  /// le `ListView` scrollable de la barre latérale (`_buildDesktop`) — un
  /// lecteur d'écran ne voyait aucune des ~13 entrées malgré un rendu et un
  /// clic fonctionnels.
  Widget _sidebarEntry(
    BuildContext context, {
    required Widget icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = selected ? Colors.white : _sidebarText;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: label,
      selected: selected,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? _sidebarActiveBg : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                IconTheme.merge(
                  data: IconThemeData(
                    size: 18,
                    color: color,
                    fill: selected ? 1 : 0,
                  ),
                  child: icon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// En-tête de groupe repliable pour le drawer mobile (#5139) — [onTap]
  /// replie/déplie sans fermer le drawer (contrairement aux entrées de
  /// destination, qui naviguent et le referment).
  Widget _groupHeaderListTile(
    BuildContext context,
    _NavRow row, {
    required VoidCallback onTap,
  }) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return ListTile(
      dense: true,
      leading: _groupHeaderIcon(context, row.collapsed),
      title: Text(
        row.group!,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.textTertiary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
      ),
      onTap: onTap,
    );
  }

  /// [dark] : fond sombre de la barre latérale desktop (#5138) — `false`
  /// (défaut) conserve le rendu clair existant du drawer mobile.
  Widget _trailing(BuildContext context, {bool dark = false}) {
    final session = widget.session;
    final cabinetName = _orNull(session.contextLabel) ?? widget.config.appTitle;
    final name = _orNull(session.displayName) ?? _proRoleLabel(session.role);
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _UserFooter(
          initials: initialsFrom(name),
          name: name,
          roleLine: '${_proRoleLabel(session.role)} · $cabinetName',
          dark: dark,
        ),
        ...widget.trailingActions,
        if (widget.onSignOut != null)
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: widget.onSignOut,
          ),
      ],
    );
    if (!dark) return column;
    return IconTheme.merge(
      data: const IconThemeData(color: _sidebarText),
      child: column,
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    List<ProNavDestination> destinations,
    List<_NavRow> rows,
    int rowIndex,
    ProNavDestination current,
  ) {
    // #6263 — cloche partagée par les 3 apps pro, `null` quand l'appelant ne
    // fournit pas de [ProShell.notificationRepository] (voir sa doc).
    final bell = _notificationsCubit == null
        ? null
        : ProNotificationsBell(
            cubit: _notificationsCubit!,
            onNotificationTap: widget.onNotificationTap,
          );

    // En mode [body] (StatefulShellRoute), la page routée porte déjà son
    // propre Scaffold/AppBar le cas échéant (ex. bouton actualiser, FAB) —
    // un second NubiaAppBar ici le dupliquerait. On ne fournit le
    // NubiaAppBar générique (titre + recherche + cloche) que dans le mode
    // [bodyBuilder] legacy, où aucune chrome par destination n'existe.
    final body = widget.body;
    final content = body != null
        ? _RouteSemanticsBoundary(child: body)
        : Scaffold(
            appBar: NubiaAppBar(
              title: current.label,
              centerTitle: false,
              actions: [
                if (widget.searchHint != null && widget.onSearchTap != null)
                  _SearchTrigger(
                    hint: widget.searchHint!,
                    onTap: widget.onSearchTap!,
                  ),
                if (bell != null) bell,
                const SizedBox(width: 8),
              ],
            ),
            body: _content(context, current),
          );

    // #6316 — en mode [body], le NubiaAppBar générique est court-circuité
    // (cf. commentaire ci-dessus) et emportait avec lui le déclencheur de
    // recherche (`_SearchTrigger`), alors que seule la duplication du titre
    // était voulue : le raccourci ⌘K (pro_shell.dart, `_registerShortcuts`)
    // restait fonctionnel mais n'avait plus aucun point d'entrée visible.
    final searchTrigger =
        widget.searchHint != null && widget.onSearchTap != null
            ? _SearchTrigger(hint: widget.searchHint!, onTap: widget.onSearchTap!)
            : null;

    // Mode [body] : aucune AppBar ne porte la recherche/la cloche (chrome de
    // la page routée, cf. commentaire ci-dessus) — une fine barre dédiée les
    // ajoute au-dessus, pour qu'elles restent partagées sans dupliquer le
    // titre.
    final contentWithBell = widget.body != null &&
            (bell != null || searchTrigger != null)
        ? Column(
            children: [
              _DesktopNotificationsBar(searchTrigger: searchTrigger, bell: bell),
              Expanded(child: content),
            ],
          )
        : content;

    return Scaffold(
      body: Row(
        children: [
          // Barre latérale libellée, 250px, fond sombre (#5138, remplace le
          // `NavigationRail` d'icônes — verbatim maquette design-v2
          // secrétariat, colonne « Proposé »). Les libellés sont toujours
          // visibles (plus de bascule icône-seule au-delà d'un seuil de
          // destinations).
          Container(
            width: _sidebarWidth,
            color: NubiaColors.n900,
            child: SafeArea(
              right: false,
              child: Column(
                children: [
                  // En-tête cabinet (#5140, maquette design-v2 secrétariat) —
                  // remplace le monogramme nu introduit par #3363/#3375.
                  _BrandHeader(
                    cabinetName: _orNull(widget.session.contextLabel) ??
                        widget.config.appTitle,
                    subtitle: widget.config.spaceLabel,
                    dark: true,
                  ),
                  // Colonne scrollable indépendante du reste : contrairement
                  // au `NavigationRail` (#4153, ne défilait pas au-delà d'une
                  // dizaine de destinations), l'excédent défile sans faire
                  // déborder l'en-tête/le pied de la barre latérale.
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      children: [
                        for (int i = 0; i < rows.length; i++)
                          if (rows[i].destination != null)
                            _sidebarEntry(
                              context,
                              icon:
                                  _iconWithBadge(context, rows[i].destination!),
                              label: rows[i].destination!.label,
                              selected: i == rowIndex,
                              onTap: () => _selectRow(destinations, rows, i),
                            )
                          else
                            _sidebarGroupHeader(
                              context,
                              rows[i],
                              onTap: () => _selectRow(destinations, rows, i),
                            ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _trailing(context, dark: true),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: contentWithBell),
        ],
      ),
    );
  }

  Widget _buildMobile(
    BuildContext context,
    List<ProNavDestination> destinations,
    List<_NavRow> rows,
    int rowIndex,
    ProNavDestination current,
  ) {
    // #6263 — même cloche partagée que le rail desktop (voir _buildDesktop).
    final bell = _notificationsCubit == null
        ? null
        : ProNotificationsBell(
            cubit: _notificationsCubit!,
            onNotificationTap: widget.onNotificationTap,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config.appTitle),
        actions: bell == null ? null : [bell, const SizedBox(width: 8)],
      ),
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
              for (int i = 0; i < rows.length; i++)
                if (rows[i].destination != null)
                  ListTile(
                    leading: _iconWithBadge(context, rows[i].destination!),
                    title: Text(rows[i].destination!.label),
                    selected: i == rowIndex,
                    onTap: () {
                      Navigator.of(context).pop();
                      _selectRow(destinations, rows, i);
                    },
                  )
                else
                  _groupHeaderListTile(
                    context,
                    rows[i],
                    onTap: () => _selectRow(destinations, rows, i),
                  ),
              const Spacer(),
              _trailing(context),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: widget.body != null
          ? _RouteSemanticsBoundary(child: widget.body!)
          : _content(context, current),
    );
  }
}

/// Isole [ProShell.body] dans son propre conteneur Semantics (#6310) : quand
/// [body] est un `StatefulNavigationShell` (`StatefulShellRoute`, praticien
/// et secrétariat), il embarque son propre `Navigator`/`Overlay` — dont la
/// route active pousse un `BlockSemantics` qui masque, par ordre de peinture
/// plutôt que par ascendance dans l'arbre de widgets, TOUT ce qui est peint
/// avant lui sous le plus proche ancêtre `Semantics(explicitChildNodes:
/// true)` commun. Ici, cet ancêtre est le nœud de route de `ProShell`
/// lui-même : sans boundary intermédiaire, `BlockSemantics` remonte jusqu'à
/// lui et efface la barre latérale/cloche/déconnexion, alors peintes AVANT
/// [body] dans le `Row`/`Column` du rail — rendues et cliquables (le rendu
/// visuel ne dépend pas des Semantics), mais absentes de l'arbre
/// d'accessibilité. `container: true` fait de [body] son propre nœud
/// Semantics : la recherche du « plus proche ancêtre commun » par
/// `BlockSemantics` s'arrête ici, sans pouvoir remonter jusqu'aux frères
/// précédents. Aucun effet en mode [ProShell.bodyBuilder] (pharmacie) :
/// ce mode ne construit aucun `Navigator` imbriqué.
class _RouteSemanticsBoundary extends StatelessWidget {
  const _RouteSemanticsBoundary({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(container: true, child: child);
  }
}

/// Fine barre au-dessus du contenu routé, seule à porter la cloche (#6263)
/// et le déclencheur de recherche globale (#6316) quand [ProShell.body] est
/// fourni (StatefulShellRoute) — ce mode-là ne passe jamais par le
/// [NubiaAppBar] de `_buildDesktop` (voir son commentaire), qui est le seul
/// autre point où ces deux éléments s'affichent.
class _DesktopNotificationsBar extends StatelessWidget {
  const _DesktopNotificationsBar({this.searchTrigger, this.bell});

  final Widget? searchTrigger;
  final Widget? bell;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      height: 48,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (searchTrigger != null) searchTrigger!,
          if (bell != null) bell!,
        ],
      ),
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

/// `null` si [value] est absent OU vide (#6170, même défaut que #6165) :
/// `??` seul ne couvre pas le cas où [AuthSession] expose une chaîne vide
/// plutôt que `null` (bootstrap de session best-effort, cf. `pro_auth_cubit.dart`).
String? _orNull(String? value) =>
    (value == null || value.isEmpty) ? null : value;

/// Libellé FR d'un [ProRole], pour le pied utilisateur du rail (#5140) — pas
/// de mapping partagé existant, [MemberRole._roleLabel] (admin_membres_page)
/// couvre un enum métier distinct.
String _proRoleLabel(ProRole role) {
  switch (role) {
    case ProRole.admin:
      return 'Administrateur';
    case ProRole.practitioner:
      return 'Praticien';
    case ProRole.secretary:
      return 'Secrétaire';
    case ProRole.pharmacist:
      return 'Pharmacien';
    case ProRole.nurse:
      return 'Infirmier';
    case ProRole.unknown:
      return 'Membre';
  }
}

/// En-tête d'identité du cabinet en haut du rail (#5140, maquette design-v2
/// secrétariat) — monogramme + nom du cabinet + sous-titre d'espace.
/// [cabinetName] vient de [AuthSession.contextLabel] (peuplé au bootstrap de
/// session depuis `GET /v1/me`, #6170) ; l'appelant retombe sur
/// [ProConfig.appTitle] tant que ce champ n'est pas disponible (`/me` en échec,
/// ou aucun cabinet/pharmacie rattaché).
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.cabinetName,
    required this.subtitle,
    this.dark = false,
  });

  final String cabinetName;
  final String subtitle;

  /// Fond sombre de la barre latérale desktop (#5138) — `false` (défaut)
  /// conserve le rendu clair existant du drawer mobile.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final cs = Theme.of(context).colorScheme;
    final titleColor = dark ? Colors.white : cs.onSurface;
    final subtitleColor = dark ? _sidebarText : tokens.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NubiaColors.brand600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'N',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            cabinetName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: subtitleColor),
          ),
        ],
      ),
    );
  }
}

/// Pied utilisateur en bas du rail (#5140, maquette design-v2 secrétariat) —
/// avatar initiales + nom + rôle·cabinet, séparé des destinations par un
/// filet ([NubiaTokens.borderSubtle], même style que `week_occupancy_card.dart`
/// / `today_flow_card.dart`).
class _UserFooter extends StatelessWidget {
  const _UserFooter({
    required this.initials,
    required this.name,
    required this.roleLine,
    this.dark = false,
  });

  final String initials;
  final String name;
  final String roleLine;

  /// Fond sombre de la barre latérale desktop (#5138) — `false` (défaut)
  /// conserve le rendu clair existant du drawer mobile.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final cs = Theme.of(context).colorScheme;
    final dividerColor =
        dark ? Colors.white.withValues(alpha: 0.08) : tokens.borderSubtle;
    final nameColor = dark ? Colors.white : cs.onSurface;
    final roleColor = dark ? _sidebarText : tokens.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, thickness: 1, color: dividerColor),
          const SizedBox(height: 8),
          NubiaAvatar(initials: initials, radius: 14),
          const SizedBox(height: 4),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: nameColor,
            ),
          ),
          Text(
            roleLine,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: roleColor),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
