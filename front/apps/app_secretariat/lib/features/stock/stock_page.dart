import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'create_stock_request_dialog.dart';
import 'stock_bloc.dart';
import 'stock_event.dart';
import 'stock_state.dart';

const _statusLabels = {
  StockRequestStatus.sent: 'Envoyée',
  StockRequestStatus.accepted: 'Acceptée',
  StockRequestStatus.rejected: 'Refusée',
  StockRequestStatus.fulfilled: 'Honorée',
  StockRequestStatus.cancelled: 'Annulée',
};

const _statusVariants = {
  StockRequestStatus.sent: StatusPillVariant.info,
  StockRequestStatus.accepted: StatusPillVariant.warning,
  StockRequestStatus.rejected: StatusPillVariant.error,
  StockRequestStatus.fulfilled: StatusPillVariant.success,
  StockRequestStatus.cancelled: StatusPillVariant.error,
};

/// Formate « jj/mm » (heure locale).
String _formatDayMonth(DateTime dt) {
  final local = dt.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}';
}

/// Formate « hh:mm » (heure locale).
String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// Formate « jj/mm · hh:mm », le format utilisé par la maquette design-v2.
String _formatDateTime(DateTime dt) =>
    '${_formatDayMonth(dt)} · ${_formatTime(dt)}';

/// Écran « Stock » côté cabinet (lot B5, #3507) : demandes de stock envoyées
/// aux pharmacies partenaires (`POST /v1/cabinet/stock-requests`) et suivi de
/// leur statut (`sent` → `accepted`/`rejected` → `fulfilled`, ou `cancelled`).
///
/// design-v2 (#5190) : shell maître-détail — liste à gauche, panneau détail
/// (dont la section « Suivi ») à droite pour la demande sélectionnée.
class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  String? _selectedId;
  String _query = '';
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    context.read<StockBloc>().add(const StockLoadRequested());
    // `autofocus` seul ne suffit pas ici : la route hôte (ModalRoute) prend
    // le focus initial en premier — demande explicite pour que ↑/↓/⏎
    // fonctionnent dès l'affichage de la liste, sans clic préalable.
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onCreate() async {
    final bloc = context.read<StockBloc>();
    final result = await showCreateStockRequestDialog(context);
    if (result != null) {
      bloc.add(StockCreateRequested(
        pharmacyId: result.pharmacyId,
        items: result.items,
      ));
    }
  }

  /// Filtre client (aucun nouvel appel réseau) sur les libellés d'article et
  /// le nom/id de pharmacie des demandes déjà chargées — #5187.
  List<StockRequest> _filterRequests(List<StockRequest> requests) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return requests;
    return requests
        .where((request) =>
            (request.pharmacy?.name ?? request.pharmacyId)
                .toLowerCase()
                .contains(query) ||
            request.items
                .any((item) => item.label.toLowerCase().contains(query)))
        .toList();
  }

  /// ↑/↓ change la sélection (surlignage + panneau), ⏎ ouvre la demande
  /// courante (la première si aucune n'est encore sélectionnée).
  KeyEventResult _handleKey(KeyEvent event, List<StockRequest> requests) {
    if (event is! KeyDownEvent || requests.isEmpty) {
      return KeyEventResult.ignored;
    }
    final currentIndex =
        _selectedId == null ? -1 : requests.indexWhere((r) => r.id == _selectedId);

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        final next = (currentIndex + 1).clamp(0, requests.length - 1);
        setState(() => _selectedId = requests[next].id);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        final prev = currentIndex <= 0 ? 0 : currentIndex - 1;
        setState(() => _selectedId = requests[prev].id);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        final index = currentIndex < 0 ? 0 : currentIndex;
        setState(() => _selectedId = requests[index].id);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    // #5188 — ⌘N ouvre la création de demande, comme les autres écrans
    // refondus. Le raccourci bulle depuis le `Focus` de la liste (l.163,
    // focus initial demandé en l.70) jusqu'à ce `CallbackShortcuts`.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _onCreate,
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stock'),
          actions: [
            IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  context.read<StockBloc>().add(const StockLoadRequested()),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: NubiaButton(
                key: const Key('new_stock_request_fab'),
                label: 'Nouvelle demande',
                icon: Icons.add,
                onPressed: _onCreate,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: NubiaBadge.label(label: '⌘N'),
            ),
          ],
        ),
        body: BlocBuilder<StockBloc, StockState>(
          builder: (context, state) {
            switch (state) {
              case StockLoading():
                return const _StockLoadingSkeleton();
              case StockError(:final message):
                return NubiaErrorWidget(
                  message: message,
                  onRetry: () => context
                      .read<StockBloc>()
                      .add(const StockLoadRequested()),
                );
              case StockLoaded(:final requests):
                if (requests.isEmpty) {
                  return const NubiaEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Aucune demande de stock',
                    subtitle:
                        'Envoyez une demande à une pharmacie partenaire.',
                  );
                }
                final filtered = _filterRequests(requests);
                final selectedIndex =
                    filtered.indexWhere((r) => r.id == _selectedId);
                final selected =
                    selectedIndex == -1 ? null : filtered[selectedIndex];

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Focus(
                        focusNode: _focusNode,
                        onKeyEvent: (node, event) =>
                            _handleKey(event, filtered),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: SizedBox(
                                  width: 280,
                                  child: NubiaSearchBar(
                                    key: const Key('stock_search'),
                                    hint: 'Article, pharmacie…',
                                    onChanged: (value) =>
                                        setState(() => _query = value),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: filtered.isEmpty
                                  ? const NubiaEmptyState(
                                      icon: Icons.search_off,
                                      title: 'Aucun résultat',
                                      subtitle:
                                          'Aucune demande ne correspond à cette recherche.',
                                    )
                                  : ListView.builder(
                                      key: const Key('stock_request_list'),
                                      padding: const EdgeInsets.all(16),
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) {
                                        final request = filtered[index];
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 12),
                                          child: _StockRequestRow(
                                            request: request,
                                            selected:
                                                request.id == _selectedId,
                                            onTap: () => setState(() =>
                                                _selectedId = request.id),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            _StockListFooter(
                              count: filtered.length,
                              total: requests.length,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (selected != null)
                      SizedBox(
                        width: 392,
                        child: _StockDetailPanel(
                          request: selected,
                          onClose: () => setState(() => _selectedId = null),
                        ),
                      ),
                  ],
                );
            }
          },
        ),
      ),
    );
  }
}

/// Squelette de chargement — lignes fantômes reprenant la structure de la
/// liste plutôt qu'un spinner nu, au même rythme que les autres écrans
/// refondus (cf. `app_pharmacie/stock_page.dart`).
class _StockLoadingSkeleton extends StatelessWidget {
  const _StockLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          _StockRequestRowSkeleton(),
          SizedBox(height: 12),
          _StockRequestRowSkeleton(),
          SizedBox(height: 12),
          _StockRequestRowSkeleton(),
        ],
      ),
    );
  }
}

class _StockRequestRowSkeleton extends StatelessWidget {
  const _StockRequestRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: NubiaSkeletonLoader(height: 16, width: 160)),
              SizedBox(width: 12),
              NubiaSkeletonLoader(height: 20, width: 72),
            ],
          ),
          SizedBox(height: 6),
          NubiaSkeletonLoader(height: 12, width: 90),
          SizedBox(height: 12),
          NubiaSkeletonLoader(height: 14, width: double.infinity),
          SizedBox(height: 6),
          NubiaSkeletonLoader(height: 14, width: double.infinity),
        ],
      ),
    );
  }
}

/// Ligne « demande de stock » de la liste maître — surlignée (fond
/// `brand50`/bordure `primary`, cf. [NubiaCardState.selected]) quand
/// sélectionnée.
class _StockRequestRow extends StatelessWidget {
  const _StockRequestRow({
    required this.request,
    required this.selected,
    required this.onTap,
  });

  final StockRequest request;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: Key('stock_request_${request.id}'),
      state: selected ? NubiaCardState.selected : NubiaCardState.interactive,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.pharmacy?.name ?? request.pharmacyId,
                      style: textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (request.pharmacy?.address != null ||
                        request.pharmacy?.phone != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [request.pharmacy?.address, request.pharmacy?.phone]
                            .whereType<String>()
                            .join(' · '),
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              StatusPill(
                label: _statusLabels[request.status]!,
                variant: _statusVariants[request.status]!,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in request.items)
            Text(
              '• ${item.quantity} × ${item.label}'
              '${item.note != null ? ' (${item.note})' : ''}',
            ),
          if (request.responseNote != null) ...[
            const SizedBox(height: 4),
            Text('Note pharmacie : ${request.responseNote}'),
          ],
        ],
      ),
    );
  }
}

/// Pied de la liste maître : raccourcis clavier + compteur affiché.
class _StockListFooter extends StatelessWidget {
  const _StockListFooter({required this.count, required this.total});

  /// Nombre de demandes affichées après filtrage (recherche).
  final int count;

  /// Nombre total de demandes chargées, avant filtrage.
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.bodySmall?.copyWith(color: tokens.textTertiary);

    return Container(
      key: const Key('stock_list_footer'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Text('↑ ↓ naviguer', style: style),
          Text('⏎ ouvrir', style: style),
          Text(
            '$count demande${count > 1 ? 's' : ''} affichée'
            '${count > 1 ? 's' : ''} sur $total',
            style: style,
          ),
        ],
      ),
    );
  }
}

/// Panneau détail (392px, cf. maquette `.det`) : en-tête, pharmacie,
/// articles demandés et suivi de la demande sélectionnée.
class _StockDetailPanel extends StatelessWidget {
  const _StockDetailPanel({required this.request, required this.onClose});

  final StockRequest request;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    return Container(
      key: Key('stock_detail_panel_${request.id}'),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: tokens.borderSubtle)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Demande du ${_formatDateTime(request.createdAt)}',
                    style: textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  label: _statusLabels[request.status]!,
                  variant: _statusVariants[request.status]!,
                ),
                IconButton(
                  key: const Key('stock_detail_close'),
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 12),
            NubiaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.pharmacy?.name ?? request.pharmacyId,
                    style: textTheme.titleSmall,
                  ),
                  if (request.pharmacy?.address != null ||
                      request.pharmacy?.phone != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [request.pharmacy?.address, request.pharmacy?.phone]
                          .whereType<String>()
                          .join(' · '),
                      style: textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Articles demandés', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final item in request.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${item.quantity} × ${item.label}'
                  '${item.note != null ? ' (${item.note})' : ''}',
                ),
              ),
            const SizedBox(height: 16),
            Text('Suivi', style: textTheme.titleSmall),
            const SizedBox(height: 12),
            _StockTimeline(request: request),
            if (request.responseNote != null) ...[
              const SizedBox(height: 16),
              Text(
                'Note pharmacie : ${request.responseNote}',
                style: textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section « Suivi » : timeline à 3 étapes fixes (#5190). Puce pleine = fait,
/// vide = à venir. `respondedAt`/`fulfilledAt` ne sont pas toujours renvoyés
/// par le back (résolveur pharmacie / horodatage réponse : tickets data
/// dédiés) — repli `—` quand l'horodatage est indisponible.
class _StockTimeline extends StatelessWidget {
  const _StockTimeline({required this.request});

  final StockRequest request;

  static const _steps = [
    'Demande envoyée',
    'Réponse de la pharmacie',
    'Réception au cabinet',
  ];

  bool _stepDone(int index) {
    switch (index) {
      case 0:
        return true;
      case 1:
        return request.status == StockRequestStatus.accepted ||
            request.status == StockRequestStatus.rejected ||
            request.status == StockRequestStatus.fulfilled;
      default:
        return request.status == StockRequestStatus.fulfilled;
    }
  }

  String _stepSubtitle(int index) {
    switch (index) {
      case 0:
        return _formatDateTime(request.createdAt);
      case 1:
        final respondedAt = request.respondedAt;
        return respondedAt != null ? _formatDateTime(respondedAt) : '—';
      default:
        final fulfilledAt = request.fulfilledAt;
        return fulfilledAt != null ? _formatDateTime(fulfilledAt) : '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      key: const Key('stock_suivi_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _steps.length; i++)
          Padding(
            key: Key('stock_suivi_step_$i'),
            padding: EdgeInsets.only(bottom: i < _steps.length - 1 ? 12 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _stepDone(i) ? cs.primary : Colors.transparent,
                    border: Border.all(
                      color: _stepDone(i) ? cs.primary : tokens.borderSubtle,
                      width: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _steps[i],
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _stepSubtitle(i),
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
