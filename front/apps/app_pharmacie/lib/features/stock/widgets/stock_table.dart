import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../stock_bloc.dart';
import '../stock_delay.dart';
import '../stock_status.dart';

/// Largeurs des colonnes du tableau des demandes de stock (design-v2,
/// #6948) — grille maquette
/// `Reçue | Cabinet | Articles demandés | Lignes | Statut | Action`, jumelle
/// de la grille devis (`devis_table.dart`, #6454) sur la même maquette.
class _StockColumns {
  const _StockColumns._();

  static const double gap = 12;
  static const double recue = 96;
  static const double articles = 200;
  static const double lignes = 74;
  static const double statut = 130;
  static const double action = 176;

  /// Largeur minimale de la colonne `Expanded` (Cabinet) — même défense
  /// qu'en dessous de laquelle l'en-tête se rend verticalement, cf.
  /// `_DevisColumns.patientMin` (devis_table.dart, #6985).
  static const double cabinetMin = 140;

  /// Largeur minimale du tableau entier : en dessous, [StockTable] défile
  /// horizontalement plutôt que d'écraser la colonne Cabinet — même
  /// stratégie que le tableau devis (#6579/#6985).
  static const double minTotalWidth = recue +
      gap +
      cabinetMin +
      gap +
      articles +
      gap +
      lignes +
      gap +
      statut +
      gap +
      action +
      32;
}

class StockTableHeader extends StatelessWidget {
  const StockTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: tokens.textTertiary,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          SizedBox(width: _StockColumns.recue, child: Text('Reçue', style: style)),
          const SizedBox(width: _StockColumns.gap),
          Expanded(child: Text('Cabinet', style: style)),
          const SizedBox(width: _StockColumns.gap),
          SizedBox(
            width: _StockColumns.articles,
            child: Text('Articles demandés', style: style),
          ),
          const SizedBox(width: _StockColumns.gap),
          SizedBox(
            width: _StockColumns.lignes,
            child: Text('Lignes', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: _StockColumns.gap),
          SizedBox(width: _StockColumns.statut, child: Text('Statut', style: style)),
          const SizedBox(width: _StockColumns.gap),
          SizedBox(
            width: _StockColumns.action,
            child: Text('Action', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// Tableau des demandes de stock complet — en-tête + lignes (#6948), jumeau
/// de [DevisTable] (devis_table.dart) sur la même maquette : même défilement
/// horizontal en dessous de [_StockColumns.minTotalWidth] plutôt que
/// d'écraser la colonne Cabinet.
class StockTable extends StatelessWidget {
  const StockTable({
    super.key,
    required this.requests,
    required this.onRequestTap,
    required this.onAccept,
    required this.onReject,
    this.selectedRequestId,
    this.respondingId,
  });

  final List<StockRequest> requests;
  final ValueChanged<String> onRequestTap;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onReject;
  final String? selectedRequestId;
  final String? respondingId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < _StockColumns.minTotalWidth
            ? _StockColumns.minTotalWidth
            : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Column(
              children: [
                const StockTableHeader(),
                Expanded(
                  child: requests.isEmpty
                      ? const NubiaEmptyState(
                          icon: Icons.search_off,
                          title: 'Aucun résultat',
                          subtitle:
                              'Aucune demande de stock ne correspond à ce filtre.',
                        )
                      : ListView.builder(
                          key: const Key('stock_request_list'),
                          padding: EdgeInsets.zero,
                          itemCount: requests.length,
                          itemBuilder: (ctx, i) => StockTableRow(
                            request: requests[i],
                            onTap: () => onRequestTap(requests[i].id),
                            active: selectedRequestId == requests[i].id,
                            responding: respondingId == requests[i].id,
                            onAccept: () => onAccept(requests[i].id),
                            onReject: () => onReject(requests[i].id),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Résumé de la colonne Articles demandés : libellés des lignes concaténés,
/// et sous-ligne « N unités » (maquette design-v2 — écart #6948).
({String main, String sub}) _articlesSummary(StockRequest request) {
  final main = request.items.map((item) => item.label).join(', ');
  final totalUnits =
      request.items.fold<int>(0, (sum, item) => sum + item.quantity);
  return (
    main: main.isEmpty ? '—' : main,
    sub: '$totalUnits unité${totalUnits > 1 ? 's' : ''}',
  );
}

/// Ligne du tableau des demandes de stock (design-v2, #6948) : colonnes
/// Reçue (date + délai), Cabinet, Articles demandés (résumé), Lignes
/// (nombre), Statut, Action. La ligne entière est cliquable (ouvre le volet
/// de détail) sauf les boutons d'action, qui gardent leur comportement
/// propre — même contrat que [DevisTableRow] (devis_table.dart).
class StockTableRow extends StatelessWidget {
  const StockTableRow({
    super.key,
    required this.request,
    this.onTap,
    this.active = false,
    this.responding = false,
    required this.onAccept,
    required this.onReject,
  });

  final StockRequest request;
  final VoidCallback? onTap;
  final bool active;
  final bool responding;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final textTheme = theme.textTheme;
    final delay = stockDelayOf(request);
    final delayColor = switch (delay.tone) {
      StockDelayTone.neutral => tokens.textTertiary,
      StockDelayTone.soon => tokens.warningFg,
      StockDelayTone.late => tokens.dangerFg,
    };
    final articles = _articlesSummary(request);
    final lineCount = request.items.length;

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _StockColumns.recue,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatShortDate(request.createdAt),
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    delay.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: delayColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _StockColumns.gap),
            Expanded(
              child: Row(
                children: [
                  NubiaAvatar(
                    initials: NubiaInitials.of(request.cabinetName ?? '?'),
                    radius: 16,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      request.cabinetName ?? 'Cabinet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _StockColumns.gap),
            SizedBox(
              width: _StockColumns.articles,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    articles.main,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium,
                  ),
                  Text(
                    articles.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _StockColumns.gap),
            SizedBox(
              width: _StockColumns.lignes,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$lineCount',
                    textAlign: TextAlign.right,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  Text(
                    lineCount > 1 ? 'lignes' : 'ligne',
                    style: textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _StockColumns.gap),
            SizedBox(
              width: _StockColumns.statut,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: stockStatusLabel(request.status),
                  variant: stockStatusVariant(request.status),
                ),
              ),
            ),
            const SizedBox(width: _StockColumns.gap),
            SizedBox(
              width: _StockColumns.action,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _StockRowAction(
                    request: request,
                    responding: responding,
                    onAccept: onAccept,
                    onReject: onReject,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: active ? NubiaColors.brand50 : Colors.transparent,
          foregroundDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: active ? NubiaColors.brand700 : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('stock_request_${request.id}'),
              onTap: onTap,
              child: row,
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
      ],
    );
  }
}

/// Bouton d'action contextuel au statut (#6948) : « Accepter »/« Refuser »
/// pour une demande reçue (les dialogues associés restent portés par la page
/// — `_askAcceptNote`/`_askRejectNote`, motif de refus réellement
/// obligatoire, cf. `stock_page.dart`), « Marquer honorée » pour une demande
/// acceptée. Aucune action pour les demandes honorées/refusées/annulées,
/// comme sur l'ancienne carte.
class _StockRowAction extends StatelessWidget {
  const _StockRowAction({
    required this.request,
    required this.responding,
    required this.onAccept,
    required this.onReject,
  });

  final StockRequest request;
  final bool responding;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    switch (request.status) {
      case StockRequestStatus.sent:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NubiaButton(
              key: Key('stock_accept_${request.id}'),
              label: 'Accepter',
              size: NubiaButtonSize.sm,
              isLoading: responding,
              onPressed: responding ? null : onAccept,
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 32,
              child: OutlinedButton(
                key: Key('stock_reject_${request.id}'),
                onPressed: responding ? null : onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.dangerFg,
                  side: const BorderSide(color: NubiaColors.dangerBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Refuser',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        );
      case StockRequestStatus.accepted:
        return NubiaButton(
          key: Key('stock_fulfill_${request.id}'),
          label: 'Marquer honorée',
          size: NubiaButtonSize.sm,
          isLoading: responding,
          onPressed: responding
              ? null
              : () => context.read<StockBloc>().add(StockRespondRequested(
                  request.id, StockRequestResponse.fulfill)),
        );
      case StockRequestStatus.rejected:
      case StockRequestStatus.fulfilled:
      case StockRequestStatus.cancelled:
        return const SizedBox.shrink();
    }
  }
}

String _formatShortDate(DateTime d) {
  final local = d.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}';
}
