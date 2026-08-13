import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'stock_bloc.dart';
import 'stock_delay.dart';

/// Demandes de stock reçues des cabinets — corps de la destination « Stock ».
class StockView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return BlocBuilder<StockBloc, StockState>(
      builder: (context, state) {
        switch (state) {
          case StockLoading():
            return const Center(child: CircularProgressIndicator());
          case StockError(:final message):
            return NubiaErrorWidget(
              message: message,
              onRetry: () =>
                  context.read<StockBloc>().add(const StockLoadRequested()),
            );
          case StockLoaded(:final requests, :final respondingId):
            if (requests.isEmpty) {
              return const NubiaEmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Aucune demande de stock',
                subtitle:
                    'Les demandes envoyées par les cabinets apparaîtront ici.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final request = requests[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _StockRequestCard(
                    request: request,
                    responding: respondingId == request.id,
                  ),
                );
              },
            );
        }
      },
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
            Text(
              '• ${item.quantity} × ${item.label}'
              '${item.note != null ? ' (${item.note})' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
          if (request.responseNote != null) ...[
            const SizedBox(height: 4),
            Text('Note : ${request.responseNote}',
                style: theme.textTheme.bodySmall),
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
}
