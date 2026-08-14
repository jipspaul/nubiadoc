import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'stock_bloc.dart';
import 'stock_delay.dart';
import 'stock_status_facet_chip.dart';

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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                          onTap: () => setState(() => _facet = status),
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
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final request = filtered[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _StockRequestCard(
                                request: request,
                                responding: respondingId == request.id,
                              ),
                            );
                          },
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

class _StockRequestCard extends StatelessWidget {
  const _StockRequestCard({required this.request, required this.responding});

  final StockRequest request;
  final bool responding;

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
          const SizedBox(height: 8),
          for (final item in request.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '• ${item.quantity} × ${item.label}'
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
                        : () => _askRejectNote(context, bloc),
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

  Future<void> _askRejectNote(BuildContext context, StockBloc bloc) async {
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
        request.id,
        StockRequestResponse.reject,
        note: note,
      ));
    }
  }

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
