import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'lab_work_order_due.dart';
import 'lab_work_order_metrics.dart';
import 'lab_work_orders_bloc.dart';
import 'lab_work_orders_event.dart';
import 'lab_work_orders_state.dart';

/// Ordre de progression (miroir de `STATUS_ORDER`, `api/src/lab_work_orders.rs`,
/// #4148) — sert à la fois au groupement de l'affichage et au calcul du
/// prochain statut proposé par le bouton "Avancer".
const _kStatusOrder = ['sent', 'try_in', 'returned', 'fitted'];

const _kStatusLabels = <String, String>{
  'sent': 'Envoyé au labo',
  'try_in': 'Essayage',
  'returned': 'Retourné',
  'fitted': 'Posé',
};

const _kStatusVariants = <String, StatusPillVariant>{
  'sent': StatusPillVariant.info,
  'try_in': StatusPillVariant.warning,
  'returned': StatusPillVariant.warning,
  'fitted': StatusPillVariant.success,
};

/// Couleur de la pastille d'en-tête de colonne (maquette design-v2, point 3) :
/// `--infoFg`, `--warnFg`, `--brand600`, `--n400` dans l'ordre de
/// `_kStatusOrder`. Distinct de [_kStatusVariants] (couleur du `StatusPill`
/// affiché sur chaque carte), qui suit une autre convention.
Color _statusDotColor(BuildContext context, String status) {
  final tokens = Theme.of(context).extension<NubiaTokens>()!;
  switch (status) {
    case 'sent':
      return tokens.infoFg;
    case 'try_in':
      return tokens.warningFg;
    case 'returned':
      return NubiaColors.brand600;
    default:
      return NubiaColors.n400;
  }
}

/// Libellé du bouton d'avancement selon le statut courant (#5061, point 4 de
/// la maquette) : annonce l'effet de la transition plutôt qu'un « Avancer »
/// générique, sans changer l'événement émis par [_advance].
const _kStatusTransitionLabels = <String, String>{
  'sent': "Passer à l'essayage",
  'try_in': 'Marquer retourné',
  'returned': 'Programmer la pose',
};

/// `sentAt` (ISO 8601) → `dd/MM/yyyy`, même convention que
/// `patient_fiche.dart` (pas de dépendance `intl` dans ce package).
String _formatSentAt(String iso) {
  final d = DateTime.parse(iso);
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

/// Initiales pour `NubiaAvatar` dérivées de `patientDisplayName` (#5058) :
/// première lettre des deux premiers mots (« Julie Martin » → « JM »).
String _initialsOf(String displayName) {
  final words = displayName.trim().split(RegExp(r'\s+'));
  final letters = words
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0].toUpperCase());
  return letters.join();
}

/// Écran « Travaux de laboratoire » côté cabinet (#4149) : bons de travaux
/// prothétiques groupés par statut, avec action d'avancement de statut.
class LabWorkOrdersPage extends StatefulWidget {
  const LabWorkOrdersPage({super.key});

  @override
  State<LabWorkOrdersPage> createState() => _LabWorkOrdersPageState();
}

class _LabWorkOrdersPageState extends State<LabWorkOrdersPage> {
  @override
  void initState() {
    super.initState();
    context.read<LabWorkOrdersBloc>().add(const LabWorkOrdersLoadRequested());
  }

  void _advance(LabWorkOrder order) {
    final index = _kStatusOrder.indexOf(order.status);
    if (index < 0 || index >= _kStatusOrder.length - 1) return;
    context.read<LabWorkOrdersBloc>().add(LabWorkOrdersStatusChangeRequested(
          orderId: order.id,
          status: _kStatusOrder[index + 1],
        ));
  }

  /// Action de relance labo (#5062, point 5 de la maquette) : sur un bon en
  /// retard, relancer le labo est la bonne réponse — pas avancer le statut.
  /// Aucun endpoint de relance n'existe côté API : feedback local en
  /// attendant l'intégration, on ne touche pas au statut du bon.
  void _relaunchLab(LabWorkOrder order) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Labo relancé')),
    );
  }

  /// Bon actif (non `fitted`) dont la date de retour attendue est dépassée —
  /// même prédicat que [computeLabWorkOrderMetrics] (#5063).
  bool _isOverdue(LabWorkOrder order, DateTime now) {
    if (order.status == _kStatusOrder.last) return false;
    final expectedReturnAt = order.expectedReturnAt;
    if (expectedReturnAt == null) return false;
    return DateTime.parse(expectedReturnAt).isBefore(now);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Travaux de laboratoire'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<LabWorkOrdersBloc>()
                .add(const LabWorkOrdersLoadRequested()),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: NubiaButton(
              key: const Key('lab_work_orders_new_button'),
              label: 'Nouveau bon',
              icon: Icons.add,
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Création de bon de travail à venir — bientôt disponible.'),
                ),
              ),
            ),
          ),
        ],
      ),
      body: BlocConsumer<LabWorkOrdersBloc, LabWorkOrdersState>(
        // Seul le rechargement échoué avec des bons déjà affichés déclenche
        // la snackbar : l'erreur du tout premier chargement est déjà portée
        // par `NubiaErrorWidget` plein écran, une seule surface à la fois
        // (#5067).
        listenWhen: (_, s) =>
            s is LabWorkOrdersLoaded && s.errorMessage != null,
        listener: (context, state) {
          if (state is LabWorkOrdersLoaded && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!)),
            );
          }
        },
        builder: (context, state) {
          switch (state) {
            case LabWorkOrdersLoading():
              return ListView(
                key: const Key('lab_work_orders_loading'),
                padding: const EdgeInsets.all(16),
                children: [
                  for (final status in _kStatusOrder) ...[
                    Padding(
                      key: Key('lab_work_group_skeleton_$status'),
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Text(
                        _kStatusLabels[status] ?? status,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    for (var i = 0; i < 2; i++)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child:
                            NubiaSkeletonLoader(height: 88, borderRadius: 12),
                      ),
                  ],
                ],
              );
            case LabWorkOrdersError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context
                    .read<LabWorkOrdersBloc>()
                    .add(const LabWorkOrdersLoadRequested()),
              );
            case LabWorkOrdersLoaded(:final orders, :final updatingId):
              if (orders.isEmpty) {
                return const NubiaEmptyState(
                  key: Key('lab_work_orders_empty'),
                  icon: Icons.local_shipping_outlined,
                  title: 'Aucun bon de travail',
                );
              }
              final now = DateTime.now();
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LabWorkOrdersMetricsBand(orders: orders),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        key: const Key('lab_work_orders_list'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final status in _kStatusOrder) ...[
                            if (status != _kStatusOrder.first)
                              const SizedBox(width: 16),
                            Expanded(
                              child: _LabWorkStatusColumn(
                                status: status,
                                orders: orders
                                    .where((o) => o.status == status)
                                    .toList(growable: false),
                                updatingId: updatingId,
                                now: now,
                                isOverdue: _isOverdue,
                                onAdvance: _advance,
                                onRelaunchLab: _relaunchLab,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
          }
        },
      ),
    );
  }
}

/// Bande de 4 [MetricTile] dérivés des bons (#5063, point 7 de la maquette) :
/// aucun total, aucun filtre — juste de quoi répondre aux questions du matin.
class _LabWorkOrdersMetricsBand extends StatelessWidget {
  const _LabWorkOrdersMetricsBand({required this.orders});

  final List<LabWorkOrder> orders;

  @override
  Widget build(BuildContext context) {
    final metrics = computeLabWorkOrderMetrics(orders, now: DateTime.now());

    return Row(
      key: const Key('lab_work_metrics_band'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: MetricTile(
            key: const Key('lab_work_metric_in_progress'),
            icon: Icons.hourglass_top_outlined,
            value: '${metrics.inProgressCount}',
            label: 'bons en cours',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricTile(
            key: const Key('lab_work_metric_overdue'),
            icon: Icons.error_outline,
            value: '${metrics.overdueCount}',
            label: 'en retard',
            variant: MetricTileVariant.danger,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricTile(
            key: const Key('lab_work_metric_due_this_week'),
            icon: Icons.event_outlined,
            value: '${metrics.dueThisWeekCount}',
            label: 'attendus cette semaine',
            variant: MetricTileVariant.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricTile(
            key: const Key('lab_work_metric_committed'),
            icon: Icons.payments_outlined,
            value: NubiaMoney.formatCents(metrics.committedCents),
            label: 'engagé chez les labos',
          ),
        ),
      ],
    );
  }
}

/// Colonne d'une des 4 étapes du pipeline (maquette design-v2, point 3) :
/// en-tête (pastille + libellé + compteur) puis les bons de ce statut,
/// scrollables indépendamment des 3 autres colonnes. Reste visible même sans
/// bon — seule la liste de cartes est vide, pas la colonne.
class _LabWorkStatusColumn extends StatelessWidget {
  const _LabWorkStatusColumn({
    required this.status,
    required this.orders,
    required this.updatingId,
    required this.now,
    required this.isOverdue,
    required this.onAdvance,
    required this.onRelaunchLab,
  });

  final String status;
  final List<LabWorkOrder> orders;
  final String? updatingId;
  final DateTime now;
  final bool Function(LabWorkOrder order, DateTime now) isOverdue;
  final void Function(LabWorkOrder order) onAdvance;
  final void Function(LabWorkOrder order) onRelaunchLab;

  @override
  Widget build(BuildContext context) {
    // Maquette (point 3) : le compteur "Posé" est borné au mois en cours,
    // les bons posés plus anciens étant archivés (cf. note en bas de
    // colonne) — les 3 autres colonnes affichent le total brut.
    final counterLabel = status == _kStatusOrder.last
        ? '${orders.length} ce mois'
        : '${orders.length}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          key: Key('lab_work_group_$status'),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _statusDotColor(context, status),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _kStatusLabels[status] ?? status,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                counterLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final order in orders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NubiaCard(
                    key: Key('lab_work_order_${order.id}'),
                    backgroundColor: isOverdue(order, now)
                        ? Theme.of(context).extension<NubiaTokens>()!.dangerBg
                        : null,
                    borderColor: isOverdue(order, now)
                        ? NubiaColors.dangerBorder
                        : null,
                    child: isOverdue(order, now)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _LabWorkOrderInfo(order: order, now: now),
                              const SizedBox(height: 12),
                              NubiaButton(
                                key: Key(
                                    'lab_work_order_relaunch_${order.id}'),
                                label: 'Relancer le labo',
                                icon: Icons.call,
                                isLoading: updatingId == order.id,
                                onPressed: updatingId == order.id
                                    ? null
                                    : () => onRelaunchLab(order),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _LabWorkOrderInfo(order: order, now: now),
                              if (order.status != _kStatusOrder.last) ...[
                                const SizedBox(height: 12),
                                FilledButton.tonal(
                                  key: Key(
                                      'lab_work_order_advance_${order.id}'),
                                  onPressed: updatingId == order.id
                                      ? null
                                      : () => onAdvance(order),
                                  child: updatingId == order.id
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : Text(
                                          _kStatusTransitionLabels[
                                                  order.status] ??
                                              'Avancer',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              if (status == _kStatusOrder.last)
                const Padding(
                  key: Key('lab_work_column_fitted_archive_note'),
                  padding: EdgeInsets.only(top: 4, bottom: 12),
                  child: _LabWorkArchiveNote(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// État vide doux en bas de la colonne « Posé » (maquette design-v2, point
/// 3) : explique pourquoi les bons posés plus anciens n'apparaissent pas,
/// affiché en permanence (pas seulement quand la colonne est vide).
class _LabWorkArchiveNote extends StatelessWidget {
  const _LabWorkArchiveNote();

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.history, size: 16, color: onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Les bons posés sont archivés après 30 jours',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Bloc labo + statut + pied de carte (date d'envoi, prix), commun aux deux
/// rendus de carte (bon en retard ou non, #5062).
class _LabWorkOrderInfo extends StatelessWidget {
  const _LabWorkOrderInfo({required this.order, required this.now});

  final LabWorkOrder order;

  /// Heure de référence pour le calcul du repère de délai (#5059) — passée
  /// par la page plutôt que `DateTime.now()` ici, pour rester cohérente
  /// avec `isOverdue` déjà calculé une seule fois par rendu.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final due = labWorkOrderDueOf(
      status: order.status,
      expectedReturnAt: order.expectedReturnAt,
      now: now,
    );
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final (dueIcon, dueColor) = switch (due?.tone) {
      LabWorkOrderDueTone.overdue => (Icons.error, tokens.dangerFg),
      LabWorkOrderDueTone.soon => (Icons.schedule, tokens.warningFg),
      LabWorkOrderDueTone.onTime => (Icons.schedule, tokens.textTertiary),
      null => (null, onSurfaceVariant),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            NubiaAvatar(
              initials: _initialsOf(order.patientDisplayName),
              radius: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                order.patientDisplayName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (order.toothFdi != null) ...[
              const SizedBox(width: 8),
              _ToothFdiBadge(toothFdi: order.toothFdi!),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                order.workNature ?? 'Non rattaché à un devis',
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            StatusPill(
              key: Key('lab_work_order_status_${order.id}'),
              label: _kStatusLabels[order.status] ?? order.status,
              variant: _kStatusVariants[order.status] ?? StatusPillVariant.info,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.precision_manufacturing, size: 14, color: onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                order.labName,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          key: Key('lab_work_order_footer_${order.id}'),
          children: [
            Expanded(
              child: Row(
                children: [
                  if (dueIcon != null) ...[
                    Icon(dueIcon, size: 14, color: dueColor),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      due?.label ?? 'Envoyé le ${_formatSentAt(order.sentAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: dueColor,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              NubiaMoney.formatCents(order.purchasePriceCents),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Pastille sombre carrée = n° dent FDI (maquette design-v2, point 1,
/// #5058) — distincte du [StatusPill] (couleur/forme), pas un statut.
class _ToothFdiBadge extends StatelessWidget {
  const _ToothFdiBadge({required this.toothFdi});

  final String toothFdi;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: NubiaColors.n800,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        toothFdi,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: NubiaColors.n0,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
