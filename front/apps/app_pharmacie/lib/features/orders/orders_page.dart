import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../order_detail/order_detail_page.dart';
import 'orders_bloc.dart';
import 'orders_event.dart';
import 'orders_state.dart';
import 'widgets/order_row.dart';
import 'widgets/orders_aside.dart';
import 'widgets/orders_kpis.dart';
import 'widgets/orders_list_footer.dart';
import 'widgets/pickup_order_picker_sheet.dart';

/// Corps de l'écran « Commandes » — file (tableau) + colonne latérale.
/// Consommable dans le bodyBuilder du ProShell. L'aside (ou le détail d'une
/// commande, cf. [selectedOrderId]) se replie sous [_asideBreakpoint] de
/// largeur disponible.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key, this.selectedOrderId});

  /// Commande ouverte via `/orders/:id` (#6627). Non nul : la file reste
  /// affichée dans la colonne de gauche pendant que le détail occupe la
  /// colonne de droite — le pharmacien passe d'une commande à l'autre sans
  /// perdre la file (maquette design-v2, « File du jour »). `null` (défaut) :
  /// comportement inchangé (aside « À traiter »).
  final String? selectedOrderId;

  static const _asideBreakpoint = 900.0;

  /// Largeur figée de la file une fois la 3ᵉ colonne financée. #7556 la
  /// figeait à 620 px (gabarit d'une fenêtre très large) ; #7571 corrige :
  /// à 1440, le viewport que la maquette déclare elle-même, une file aussi
  /// large ne laisse plus aucune place à l'ordonnance. La maquette montre à
  /// ce viewport une file compacte (« File du jour », 288 px dans le HTML de
  /// la maquette). 360 px est le plus proche qu'on puisse en tenir sans
  /// faire déborder l'indicateur de fraîcheur (« Mise à jour il y a … ») une
  /// fois la ligne de filtres passée en [Wrap] (cf. plus bas) — en dessous,
  /// son texte seul dépasse la largeur de colonne.
  static const _wideQueueColumnWidth = 360.0;

  /// Seuil (largeur *disponible* du corps, jamais `MediaQuery` — cf. #6386)
  /// à partir duquel le détail finance sa 3ᵉ colonne « Écrans PC » (maquette
  /// `Ecrans PC - Praticien et Pharmacie.html`, écran ③).
  ///
  /// #7556 calculait ce seuil sur le coût de [_wideQueueColumnWidth] à
  /// 620 px, ce qui le plaçait à 1552 px de corps disponible — inatteignable
  /// à 1440 px de FENÊTRE, le viewport déclaré par la maquette, puisque le
  /// rail de navigation ProShell (`_sidebarWidth`, pro_shell.dart) en
  /// consomme déjà 250 à lui seul (1440 − 250 = 1190 < 1552) : #7571.
  ///
  /// Corrigé pour être atteignable exactement à ce viewport : seuil = corps
  /// disponible à 1440 px de fenêtre (1440 − 250 de rail − 1 de
  /// [VerticalDivider] entre rail et corps dans `pro_shell.dart` = 1189) =
  /// file [_wideQueueColumnWidth] (360) + volet retrait 436 px + marges/écart
  /// de la page détail 48 px (padding 16 × 2 + écart 16 entre volets) + 345 px
  /// pour l'ordonnance. Ce dernier chiffre est en retrait des 448 px visés
  /// par #7556 (gabarit tablette) — arbitrage nécessaire tant que le rail
  /// ProShell reste à 250 px labellisé (#5138) plutôt que le rail à icônes
  /// de 58 px que montre la maquette pour cet écran.
  static const _wideDetailBreakpoint = 1189.0;

  @override
  Widget build(BuildContext context) {
    final orderId = selectedOrderId;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _asideBreakpoint) {
          return orderId == null
              ? const OrdersView()
              : OrderDetailPage(orderId: orderId);
        }
        final isWide =
            orderId != null && constraints.maxWidth >= _wideDetailBreakpoint;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: _wideQueueColumnWidth, child: OrdersView()),
              Expanded(child: OrderDetailPage(orderId: orderId, isWide: true)),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(child: OrdersView()),
            SizedBox(
              width: orderId == null ? 320 : 480,
              child: orderId == null
                  ? const OrdersAside()
                  : OrderDetailPage(orderId: orderId),
            ),
          ],
        );
      },
    );
  }
}

/// File des commandes entrantes — tableau de la file, consommable seul
/// (utilisé aussi par [OrdersScreen] sur petite largeur).
class OrdersView extends StatefulWidget {
  const OrdersView({super.key});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  Completer<void>? _refreshCompleter;
  Timer? _freshnessTicker;
  final _searchFocusNode = FocusNode();
  final _searchController = TextEditingController();
  String _query = '';

  // #7003 — « Toutes » (filter == null) reste la file de travail (statuts
  // actifs seulement, cf. OrdersLoaded.visible) : les 3 statuts terminaux
  // ci-dessous n'y sont donc pas comptés, mais restent chacun atteignables
  // via leur propre facette (et la recherche, une fois la facette active).
  static const _filters = <(String, PharmacyOrderStatus?)>[
    ('Toutes', null),
    ('Reçues', PharmacyOrderStatus.received),
    ('En préparation', PharmacyOrderStatus.preparing),
    ('Prêtes', PharmacyOrderStatus.ready),
    ('Retirées', PharmacyOrderStatus.pickedUp),
    ('Refusées', PharmacyOrderStatus.rejected),
    ('Annulées', PharmacyOrderStatus.cancelled),
  ];

  @override
  void initState() {
    super.initState();
    // Fait vivre le texte relatif de l'indicateur de fraîcheur (« il y a
    // N s ») sans attendre de nouvelle donnée réseau.
    _freshnessTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _freshnessTicker?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Filtrage 100 % client — nom du patient ou n° de commande, insensible à
  /// la casse. Se combine au filtre de statut déjà appliqué par
  /// [OrdersLoaded.visible] : aucun appel réseau supplémentaire.
  List<PharmacyOrder> _search(List<PharmacyOrder> orders) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return orders;
    return orders
        .where((order) =>
            (order.patientDisplayName ?? '').toLowerCase().contains(query) ||
            order.id.toLowerCase().contains(query) ||
            (order.orderRef ?? '').toLowerCase().contains(query))
        .toList();
  }

  /// Bouton « Scanner un retrait » de la barre d'outils (#7616) : à la
  /// différence du bouton de ligne (`OrderRow`, déjà lié à sa commande), le
  /// comptoir n'a encore choisi aucune commande — on la fait choisir parmi
  /// les commandes prêtes de la file COMPLÈTE (pas la vue filtrée/recherchée
  /// courante), puis on rejoint l'écran de scan existant.
  Future<void> _scanPickup(
    BuildContext context,
    List<PharmacyOrder> allOrders,
  ) async {
    final ready = allOrders
        .where((order) => order.status == PharmacyOrderStatus.ready)
        .toList();
    final selected = await showPickupOrderPickerSheet(context, ready);
    if (selected == null || !context.mounted) return;
    context.go('/orders/${selected.id}/pickup', extra: selected);
  }

  @override
  Widget build(BuildContext context) {
    // Surface Material transparente : la barre de recherche embarque un
    // TextField (et un InkWell de vidage) qui exigent un ancêtre Material.
    // En production OrdersView est monté dans le body du ProShell (déjà sous
    // le Material du Scaffold) ; ce Material transparent la rend aussi
    // autonome (rendue seule dans les tests / petites largeurs) sans effet
    // visuel.
    return Material(
      type: MaterialType.transparency,
      // Raccourci « / » (pied de la maquette « / rechercher ») : focus le
      // champ de recherche depuis n'importe où dans la file, tant que ce
      // champ n'a pas déjà le focus (sinon on laisse taper le caractère).
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent || _searchFocusNode.hasFocus) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.slash) {
            _searchFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          // Raccourci « S » (pied de la maquette « S scanner ») : ouvre le
          // même sélecteur que le bouton de la barre d'outils.
          if (event.logicalKey == LogicalKeyboardKey.keyS) {
            final state = context.read<OrdersBloc>().state;
            if (state is OrdersLoaded) _scanPickup(context, state.orders);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: BlocConsumer<OrdersBloc, OrdersState>(
          listener: (context, state) {
            if (state is OrdersLoaded || state is OrdersError) {
              _refreshCompleter?.complete();
              _refreshCompleter = null;
            }
          },
          builder: (context, state) {
            final currentFilter = switch (state) {
              OrdersLoaded(:final filter) => filter,
              _ => null,
            };
            final allOrders = switch (state) {
              OrdersLoaded(:final orders) => orders,
              _ => null,
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state is OrdersLoaded) OrdersKpiBanner(orders: state.orders),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  // Wrap plutôt que Row (même raison qu'en dessous, #7571) :
                  // le bouton de scan ne doit pas faire déborder la barre
                  // quand la file est resserrée (`_wideQueueColumnWidth`).
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 280,
                        child: NubiaSearchBar(
                          key: const Key('orders_search'),
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          hint: 'Patient, n° commande…',
                          onChanged: (value) => setState(() => _query = value),
                          locationChip: _query.isEmpty
                              ? const _SearchShortcutHint()
                              : null,
                        ),
                      ),
                      NubiaButton(
                        key: const Key('orders_scan_pickup'),
                        label: 'Scanner un retrait',
                        icon: Icons.qr_code_scanner,
                        variant: NubiaButtonVariant.secondary,
                        size: NubiaButtonSize.sm,
                        onPressed: allOrders == null
                            ? null
                            : () => _scanPickup(context, allOrders),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    // #7571 : Row (avec l'indicateur de fraîcheur hors
                    // Expanded) débordait dès que la file passait sous
                    // ~610 px — c'est ce qui bloquait [_wideQueueColumnWidth]
                    // à cette largeur. Un Wrap laisse l'indicateur retomber
                    // sur sa propre ligne plutôt que déborder ; à largeur
                    // normale (file complète pleine largeur, aside…), le
                    // rendu est identique, tout tient sur une seule ligne.
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (label, value) in _filters)
                        NubiaChip(
                          key: Key('orders_filter_${value?.name ?? 'all'}'),
                          label: label,
                          count: allOrders == null
                              ? null
                              : value == null
                                  ? allOrders
                                      .where(
                                          (order) => !order.status.isTerminal)
                                      .length
                                  : allOrders
                                      .where((order) => order.status == value)
                                      .length,
                          selected: value == currentFilter,
                          onTap: () => context
                              .read<OrdersBloc>()
                              .add(OrdersFilterChanged(value)),
                        ),
                      if (state is OrdersLoaded)
                        _FreshnessIndicator(updatedAt: state.updatedAt),
                    ],
                  ),
                ),
                Expanded(child: _buildBody(context, state)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, OrdersState state) {
    switch (state) {
      case OrdersLoading():
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              NubiaSkeletonLoader(height: 64),
              SizedBox(height: 8),
              NubiaSkeletonLoader(height: 64),
              SizedBox(height: 8),
              NubiaSkeletonLoader(height: 64),
            ],
          ),
        );
      case OrdersError(:final message):
        return NubiaErrorWidget(
          message: message,
          onRetry: () =>
              context.read<OrdersBloc>().add(const OrdersRefreshRequested()),
        );
      case OrdersLoaded(:final pendingOrderId):
        final orders = _search(state.visible);
        final Widget list;
        if (orders.isEmpty) {
          final query = _query.trim();
          final hasQuery = query.isNotEmpty;
          list = NubiaEmptyState(
            icon: hasQuery ? Icons.search_off : Icons.shopping_bag_outlined,
            title: hasQuery
                ? 'Aucun résultat pour « $query »'
                : 'Aucune commande',
            subtitle: hasQuery
                ? 'Essayez un autre nom de patient ou numéro de commande.'
                : 'Les ordonnances transmises par les patients '
                    'apparaîtront ici.',
            action: hasQuery
                ? NubiaButton(
                    label: 'Effacer la recherche',
                    icon: Icons.close,
                    variant: NubiaButtonVariant.secondary,
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          );
        } else {
          list = RefreshIndicator(
            onRefresh: () {
              _refreshCompleter = Completer<void>();
              context.read<OrdersBloc>().add(const OrdersRefreshRequested());
              return _refreshCompleter!.future;
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                return OrderRow(
                  order: order,
                  onTap: () => context.go('/orders/${order.id}'),
                  actionInProgress: pendingOrderId == order.id,
                );
              },
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: list),
            OrdersListFooter(
              stats: OrdersFooterStats.of(
                state.visible,
                displayedCount: orders.length,
              ),
            ),
          ],
        );
    }
  }
}

/// Indice du raccourci clavier « / » — affiché à droite du champ de
/// recherche tant qu'il est vide (maquette : pied de page « / rechercher »).
class _SearchShortcutHint extends StatelessWidget {
  const _SearchShortcutHint();

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
        '/',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textTertiary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Pastille verte + texte relatif — âge de la dernière donnée reçue.
class _FreshnessIndicator extends StatelessWidget {
  const _FreshnessIndicator({required this.updatedAt});

  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: NubiaColors.brand600,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Mise à jour il y a ${_relativeAge(updatedAt)}',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: NubiaColors.n500),
        ),
      ],
    );
  }
}

String _relativeAge(DateTime updatedAt) {
  final elapsed = DateTime.now().difference(updatedAt);
  if (elapsed.inSeconds < 60) return '${elapsed.inSeconds} s';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min';
  return '${elapsed.inHours} h';
}
