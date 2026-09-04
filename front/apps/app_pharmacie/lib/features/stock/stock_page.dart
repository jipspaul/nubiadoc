import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'stock_bloc.dart';
import 'stock_delay.dart';
import 'stock_status_facet_chip.dart';
import 'widgets/stock_kpis.dart';

/// Demandes de stock reçues des cabinets — corps de la destination « Stock ».
class StockView extends StatefulWidget {
  const StockView({super.key});

  static const _labels = {
    StockRequestStatus.sent: 'Reçue',
    StockRequestStatus.accepted: 'Acceptée',
    StockRequestStatus.rejected: 'Refusée',
    StockRequestStatus.fulfilled: 'Honorée',
    StockRequestStatus.cancelled: 'Annulée',
  };

  static const _variants = {
    StockRequestStatus.sent: StatusPillVariant.info,
    StockRequestStatus.accepted: StatusPillVariant.warning,
    StockRequestStatus.rejected: StatusPillVariant.error,
    StockRequestStatus.fulfilled: StatusPillVariant.success,
    StockRequestStatus.cancelled: StatusPillVariant.error,
  };

  @override
  State<StockView> createState() => _StockViewState();
}

class _StockViewState extends State<StockView> {
  StockRequestStatus _facet = StockRequestStatus.sent;
  String _query = '';
  String? _selectedId;

  List<StockRequest> _filter(List<StockRequest> requests) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return requests;
    return requests
        .where((request) =>
            (request.cabinetName ?? '').toLowerCase().contains(query) ||
            request.items
                .any((item) => item.label.toLowerCase().contains(query)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final facets = <(StockRequestStatus, String, Color)>[
      (StockRequestStatus.sent, 'À répondre', tokens.infoFg),
      (StockRequestStatus.accepted, 'Acceptées', tokens.warningFg),
      (StockRequestStatus.fulfilled, 'Honorées', tokens.successFg),
      (StockRequestStatus.rejected, 'Refusées', tokens.dangerFg),
    ];

    return BlocBuilder<StockBloc, StockState>(
      builder: (context, state) {
        switch (state) {
          case StockLoading():
            return const _StockLoadingSkeleton();
          case StockError(:final message):
            return NubiaErrorWidget(
              message: message,
              onRetry: () =>
                  context.read<StockBloc>().add(const StockLoadRequested()),
            );
          case StockLoaded(:final requests, :final respondingId):
            final filtered =
                _filter(requests.where((r) => r.status == _facet).toList());
            final selectedIndex =
                filtered.indexWhere((r) => r.id == _selectedId);
            final selected = selectedIndex == -1 ? null : filtered[selectedIndex];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StockKpiBanner(requests: requests),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (status, label, dotColor) in facets)
                        StockStatusFacetChip(
                          key: Key('stock_facet_${status.name}'),
                          label: label,
                          count: requests.where((r) => r.status == status).length,
                          dotColor: dotColor,
                          selected: status == _facet,
                          onTap: () => setState(() {
                            _facet = status;
                            _selectedId = null;
                          }),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 230,
                      child: NubiaSearchBar(
                        key: const Key('stock_search'),
                        hint: 'Cabinet, article…',
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const NubiaEmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'Aucune demande de stock',
                          subtitle:
                              'Les demandes envoyées par les cabinets apparaîtront ici.',
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: ListView.builder(
                                      key: const Key('stock_request_list'),
                                      padding: const EdgeInsets.all(16),
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) {
                                        final request = filtered[index];
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: _StockRequestCard(
                                            request: request,
                                            responding:
                                                respondingId == request.id,
                                            selected: request.id == _selectedId,
                                            onTap: () => setState(
                                                () => _selectedId = request.id),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  _StockListFooter(
                                    filteredCount: filtered.length,
                                    requests: requests,
                                  ),
                                ],
                              ),
                            ),
                            if (selected != null)
                              SizedBox(
                                width: 352,
                                child: _StockDetailPanel(
                                  key: Key('stock_detail_panel_${selected.id}'),
                                  request: selected,
                                  responding: respondingId == selected.id,
                                  onClose: () =>
                                      setState(() => _selectedId = null),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            );
        }
      },
    );
  }
}

/// Squelette de chargement — cartes fantômes plutôt qu'un spinner nu,
/// au même rythme que la file des commandes (`orders_page.dart`).
class _StockLoadingSkeleton extends StatelessWidget {
  const _StockLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          _StockRequestSkeletonCard(),
          SizedBox(height: 12),
          _StockRequestSkeletonCard(),
          SizedBox(height: 12),
          _StockRequestSkeletonCard(),
        ],
      ),
    );
  }
}

class _StockRequestSkeletonCard extends StatelessWidget {
  const _StockRequestSkeletonCard();

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
          SizedBox(height: 12),
          NubiaSkeletonLoader(height: 44, width: double.infinity),
        ],
      ),
    );
  }
}

/// Libellé de disponibilité d'une ligne (partagé liste + volet de détail).
String _availabilityLabel(StockItemAvailability availability) {
  return switch (availability.status) {
    StockItemAvailabilityStatus.inStock => 'En stock',
    StockItemAvailabilityStatus.limited =>
      '${availability.quantityAvailable ?? 0} dispo',
    StockItemAvailabilityStatus.outOfStock => 'Rupture',
  };
}

Color _availabilityColor(
  StockItemAvailability availability,
  NubiaTokens tokens,
) {
  return switch (availability.status) {
    StockItemAvailabilityStatus.inStock => tokens.successFg,
    StockItemAvailabilityStatus.limited => tokens.warningFg,
    StockItemAvailabilityStatus.outOfStock => tokens.dangerFg,
  };
}

/// Résumé « N lignes · M unités » d'une demande (maquette design-v2, colonne
/// LIGNES — écart #6452).
String _linesSummary(StockRequest request) {
  final totalUnits =
      request.items.fold<int>(0, (sum, item) => sum + item.quantity);
  final lineCount = request.items.length;
  return '$lineCount ligne${lineCount > 1 ? 's' : ''} · $totalUnits unités';
}

/// Ouvre un dialogue pour accepter une demande avec une note optionnelle
/// (maquette design-v2, CTA « Accepter avec une note » — écart #6452).
Future<void> _askAcceptNote(
  BuildContext context,
  StockBloc bloc,
  String requestId,
) async {
  final controller = TextEditingController();
  final note = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Accepter la demande'),
      content: NubiaTextField(
        controller: controller,
        label: 'Note (optionnelle)',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Annuler'),
        ),
        TextButton(
          key: const Key('stock_accept_note_confirm'),
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Accepter'),
        ),
      ],
    ),
  );
  if (note != null) {
    bloc.add(StockRespondRequested(
      requestId,
      StockRequestResponse.accept,
      note: note.isEmpty ? null : note,
    ));
  }
}

Future<void> _askRejectNote(
  BuildContext context,
  StockBloc bloc,
  String requestId,
) async {
  final controller = TextEditingController();
  final note = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final canConfirm = controller.text.trim().isNotEmpty;
        return AlertDialog(
          title: const Text('Refuser la demande'),
          content: NubiaTextField(
            controller: controller,
            label: 'Motif du refus',
            onChanged: (_) => setState(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              key: const Key('stock_reject_confirm'),
              onPressed: canConfirm
                  ? () =>
                      Navigator.of(dialogContext).pop(controller.text.trim())
                  : null,
              child: const Text('Refuser'),
            ),
          ],
        );
      },
    ),
  );
  if (note != null && note.isNotEmpty) {
    bloc.add(StockRespondRequested(
      requestId,
      StockRequestResponse.reject,
      note: note,
    ));
  }
}

class _StockRequestCard extends StatelessWidget {
  const _StockRequestCard({
    required this.request,
    required this.responding,
    required this.selected,
    required this.onTap,
  });

  final StockRequest request;
  final bool responding;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final bloc = context.read<StockBloc>();
    final delay = stockDelayOf(request);
    final delayColor = switch (delay.tone) {
      StockDelayTone.neutral => tokens.textTertiary,
      StockDelayTone.soon => tokens.warningFg,
      StockDelayTone.late => tokens.dangerFg,
    };

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
                      request.cabinetName ?? 'Cabinet',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      delay.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: delayColor,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: StockView._labels[request.status]!,
                variant: StockView._variants[request.status]!,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _linesSummary(request),
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.textTertiary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          for (final item in request.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${item.quantity}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${item.label}'
                      '${item.note != null ? ' (${item.note})' : ''}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (item.availability != null)
                    Text(
                      _availabilityLabel(item.availability!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _availabilityColor(item.availability!, tokens),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          if (request.responseNote != null) ...[
            const SizedBox(height: 4),
            Text('Note : ${request.responseNote}',
                style: theme.textTheme.bodySmall),
          ],
          if (request.status == StockRequestStatus.sent &&
              request.items.any(
                (item) =>
                    item.availability?.status ==
                    StockItemAvailabilityStatus.limited,
              )) ...[
            const SizedBox(height: 12),
            const _PartialAvailabilityBanner(),
          ],
          if (request.status == StockRequestStatus.sent) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: NubiaButton(
                    key: Key('stock_accept_${request.id}'),
                    label: 'Accepter',
                    isLoading: responding,
                    onPressed: responding
                        ? null
                        : () => bloc.add(StockRespondRequested(
                            request.id, StockRequestResponse.accept)),
                  ),
                ),
                const SizedBox(width: 8),
                // Refus irréversible engageant la relation commerciale : action
                // secondaire teintée danger, jamais à égalité avec l'accept.
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    key: Key('stock_reject_${request.id}'),
                    onPressed: responding
                        ? null
                        : () => _askRejectNote(context, bloc, request.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.dangerFg,
                      side: const BorderSide(color: NubiaColors.dangerBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(0, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Refuser — motif obligatoire',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (request.status == StockRequestStatus.accepted) ...[
            const SizedBox(height: 12),
            NubiaButton(
              key: Key('stock_fulfill_${request.id}'),
              label: 'Marquer honorée',
              isLoading: responding,
              onPressed: responding
                  ? null
                  : () => bloc.add(StockRespondRequested(
                      request.id, StockRequestResponse.fulfill)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pied de la liste maître (maquette design-v2, `.foot` — écart #6452) :
/// nombre affiché après filtrage / total chargé, et taux d'acceptation
/// global. Le délai moyen de réponse de la maquette reste hors périmètre :
/// `StockRequest.respondedAt` n'est renvoyé par aucun back aujourd'hui
/// (ticket data séparé, cf. commentaire équivalent côté secrétariat).
class _StockListFooter extends StatelessWidget {
  const _StockListFooter({required this.filteredCount, required this.requests});

  /// Nombre de demandes affichées après filtrage (facette + recherche).
  final int filteredCount;

  /// Nombre total de demandes chargées, avant filtrage.
  final List<StockRequest> requests;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style =
        Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens.textTertiary);

    final decided = requests
        .where((r) =>
            r.status == StockRequestStatus.accepted ||
            r.status == StockRequestStatus.rejected ||
            r.status == StockRequestStatus.fulfilled)
        .toList();
    final acceptanceRate = decided.isEmpty
        ? null
        : ((decided
                    .where((r) => r.status != StockRequestStatus.rejected)
                    .length /
                decided.length) *
            100)
            .round();

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
          Text(
            '$filteredCount demande${filteredCount > 1 ? 's' : ''} affichée'
            '${filteredCount > 1 ? 's' : ''} sur ${requests.length}',
            style: style,
          ),
          if (acceptanceRate != null)
            Text('Taux d\'acceptation : $acceptanceRate %', style: style),
        ],
      ),
    );
  }
}

/// Volet de détail (352px, cf. maquette `.det`) : articles demandés avec
/// disponibilité par ligne, et actions (« Accepter avec une note » /
/// refuser / honorer) — écart #6452, point ⑤ de la maquette : « répondre à
/// une demande suppose de savoir ce qu'on a en réserve ».
class _StockDetailPanel extends StatelessWidget {
  const _StockDetailPanel({
    super.key,
    required this.request,
    required this.responding,
    required this.onClose,
  });

  final StockRequest request;
  final bool responding;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final bloc = context.read<StockBloc>();

    return Container(
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
                    request.cabinetName ?? 'Cabinet',
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  label: StockView._labels[request.status]!,
                  variant: StockView._variants[request.status]!,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child:
                      Text('Articles demandés', style: theme.textTheme.titleSmall),
                ),
                const SizedBox(width: 8),
                Text(
                  _linesSummary(request),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: tokens.textTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in request.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${item.quantity}',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 12.5),
                          ),
                          if (item.note != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.note!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: tokens.textTertiary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (item.availability != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _availabilityLabel(item.availability!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              _availabilityColor(item.availability!, tokens),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (request.status == StockRequestStatus.sent &&
                request.items.any(
                  (item) =>
                      item.availability?.status ==
                      StockItemAvailabilityStatus.limited,
                )) ...[
              const SizedBox(height: 4),
              const _PartialAvailabilityBanner(),
            ],
            if (request.responseNote != null) ...[
              const SizedBox(height: 16),
              Text('Note : ${request.responseNote}',
                  style: theme.textTheme.bodyMedium),
            ],
            if (request.status == StockRequestStatus.sent) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: NubiaButton(
                  key: Key('stock_detail_accept_${request.id}'),
                  label: 'Accepter avec une note',
                  icon: Icons.check,
                  isLoading: responding,
                  onPressed: responding
                      ? null
                      : () => _askAcceptNote(context, bloc, request.id),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  key: Key('stock_detail_reject_${request.id}'),
                  onPressed: responding
                      ? null
                      : () => _askRejectNote(context, bloc, request.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.dangerFg,
                    side: const BorderSide(color: NubiaColors.dangerBorder),
                  ),
                  child: const Text(
                    'Refuser — motif obligatoire',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ] else if (request.status == StockRequestStatus.accepted) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: NubiaButton(
                  key: Key('stock_detail_fulfill_${request.id}'),
                  label: 'Marquer honorée',
                  isLoading: responding,
                  onPressed: responding
                      ? null
                      : () => bloc.add(StockRespondRequested(
                          request.id, StockRequestResponse.fulfill)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rappel que l'acceptation engage la totalité de la demande quand ≥ 1 ligne
/// est en disponibilité partielle : pas d'acceptation partielle possible,
/// la réserve doit être précisée dans la note de réponse.
class _PartialAvailabilityBanner extends StatelessWidget {
  const _PartialAvailabilityBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: const Key('stock_partial_availability_banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NubiaColors.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: tokens.warningFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: textTheme.bodySmall?.copyWith(color: tokens.warningFg),
                children: const [
                  TextSpan(
                    text: 'Une ligne partiellement disponible.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' Accepter engage la totalité de la demande — '
                        'précisez la réserve dans la note de réponse.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
