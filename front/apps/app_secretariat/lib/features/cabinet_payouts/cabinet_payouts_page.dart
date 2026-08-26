import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:share_plus/share_plus.dart';

import 'cabinet_payouts_bloc.dart';
import 'cabinet_payouts_event.dart';
import 'cabinet_payouts_state.dart';

/// Page complète (route dédiée) — même découpage que `CabinetStatsPage`.
class CabinetPayoutsPage extends StatelessWidget {
  const CabinetPayoutsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('cabinet_payouts_scaffold'),
      appBar: AppBar(
        title: Row(
          children: [
            const Flexible(
              child: Text(
                'Rapprochement bancaire',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 16),
            BlocBuilder<CabinetPayoutsBloc, CabinetPayoutsState>(
              builder: (context, state) {
                final month = (state is CabinetPayoutsLoaded
                        ? state.selectedMonth
                        : null) ??
                    _startOfCurrentMonth();
                return _MonthSelector(month: month);
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<CabinetPayoutsBloc>()
                .add(const CabinetPayoutsLoadRequested()),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: BlocBuilder<CabinetPayoutsBloc, CabinetPayoutsState>(
              builder: (context, state) {
                final payouts = state is CabinetPayoutsLoaded
                    ? state.payouts
                    : const <CabinetPayout>[];
                return NubiaButton(
                  key: const Key('cabinet_payouts_export_csv'),
                  label: 'Exporter (CSV)',
                  icon: Icons.download,
                  variant: NubiaButtonVariant.secondary,
                  size: NubiaButtonSize.sm,
                  onPressed: payouts.isEmpty
                      ? null
                      : () => _exportPayoutsCsv(context, payouts),
                );
              },
            ),
          ),
        ],
      ),
      body: const CabinetPayoutsBody(),
    );
  }
}

/// Export CSV des virements affichés (#5104) — destiné à l'expert-comptable
/// pour le rapprochement bancaire. Aucune donnée clinique : moyens de
/// paiement et montants uniquement.
Future<void> _exportPayoutsCsv(
  BuildContext context,
  List<CabinetPayout> payouts,
) async {
  final bytes = Uint8List.fromList(utf8.encode(_payoutsToCsv(payouts)));
  try {
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          name: 'rapprochement_virements.csv',
          mimeType: 'text/csv',
        ),
      ],
      subject: 'Rapprochement bancaire — export CSV',
    );
  } catch (_) {
    if (!context.mounted) return;
    NubiaSnackbar.show(context: context, message: "Échec de l'export CSV.");
  }
}

String _payoutsToCsv(List<CabinetPayout> payouts) {
  final buffer = StringBuffer()
    ..writeln(
      [
        'Date',
        'Prestataire',
        'Identifiant',
        'Montant reçu (EUR)',
        'Paiements internes (EUR)',
        'Écart (EUR)',
        'Statut',
      ].map(_csvField).join(','),
    );
  for (final payout in payouts) {
    final reconciled =
        payout.reconciliationStatus == PayoutReconciliationStatus.reconciled;
    buffer.writeln(
      [
        _formatDate(payout.arrivalDate),
        _providerLabel(payout.provider),
        payout.id,
        _csvAmount(payout.amountCents),
        _csvAmount(payout.internalPaymentsTotalCents),
        _csvAmount(payout.differenceCents),
        reconciled ? 'Rapproché' : 'À vérifier',
      ].map(_csvField).join(','),
    );
  }
  return buffer.toString();
}

/// Centimes → décimal point (ex. `12.34`), exploitable tel quel par un
/// tableur — pas de symbole monétaire ni de virgule française.
String _csvAmount(int cents) => (cents / 100).toStringAsFixed(2);

String _csvField(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String _providerLabel(PayoutProvider provider) => switch (provider) {
      PayoutProvider.stripe => 'Stripe',
      PayoutProvider.gocardless => 'GoCardless',
    };

/// Code court de la pastille provider (maquette design-v2, point 5) — `STR`
/// pour Stripe, `GCL` pour GoCardless.
String _providerCode(PayoutProvider provider) => switch (provider) {
      PayoutProvider.stripe => 'STR',
      PayoutProvider.gocardless => 'GCL',
    };

DateTime _startOfCurrentMonth() {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
}

const _frenchMonths = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

String _monthLabel(DateTime month) =>
    '${_frenchMonths[month.month - 1]} ${month.year}';

/// Sélecteur de mois de l'en-tête (design-v2, point 4b) — le rapprochement
/// est un travail mensuel, absent de l'écran jusqu'ici.
class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    void change(int deltaMonths) => context.read<CabinetPayoutsBloc>().add(
          CabinetPayoutsMonthChanged(
            DateTime(month.year, month.month + deltaMonths),
          ),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('cabinet_payouts_month_prev'),
            icon: const Icon(Icons.chevron_left, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => change(-1),
          ),
          Text(
            _monthLabel(month),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          IconButton(
            key: const Key('cabinet_payouts_month_next'),
            icon: const Icon(Icons.chevron_right, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => change(1),
          ),
        ],
      ),
    );
  }
}

String _pad2(int n) => n.toString().padLeft(2, '0');

String _formatDate(DateTime d) => '${_pad2(d.day)}/${_pad2(d.month)}/${d.year}';

String _shortDate(DateTime d) => '${_pad2(d.day)}/${_pad2(d.month)}';

/// Sens de l'écart (#5108) selon le signe de `differenceCents` —
/// information absente de l'ancien encart, désormais explicite.
String _gapSensePhrase(int differenceCents) => differenceCents < 0
    ? 'la banque a reçu moins que ce qui a été encaissé'
    : 'la banque a reçu plus que ce qui a été encaissé';

/// Paiement interne non rapprochable par le prestataire dont le montant
/// égale exactement l'écart (#5110) — signale une « piste probable » sans
/// jamais rapprocher automatiquement quoi que ce soit.
InternalPayment? _probableLead(CabinetPayout payout) {
  for (final payment in payout.internalPayments) {
    if (!payment.reconcilableByProvider &&
        payment.amountCents == payout.differenceCents.abs()) {
      return payment;
    }
  }
  return null;
}

/// Corps de l'écran — consommable dans `ProShell.bodyBuilder`.
class CabinetPayoutsBody extends StatelessWidget {
  const CabinetPayoutsBody({super.key, this.demoMode = true});

  /// Tant qu'aucun compte Stripe/GoCardless n'est réellement connecté, les
  /// virements affichés restent des données mock (#5099, cf.
  /// `cabinet_payout.dart`) — pas de champ dédié côté domaine pour le
  /// signaler, donc ce booléen local. À câbler sur le vrai signal de
  /// connexion quand il existera.
  final bool demoMode;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CabinetPayoutsBloc, CabinetPayoutsState>(
      builder: (context, state) {
        return switch (state) {
          CabinetPayoutsLoading() => const _CabinetPayoutsSkeleton(),
          CabinetPayoutsError(:final message) => NubiaErrorWidget(
              key: const Key('cabinet_payouts_error'),
              message: message,
              onRetry: () => context
                  .read<CabinetPayoutsBloc>()
                  .add(const CabinetPayoutsLoadRequested()),
            ),
          CabinetPayoutsLoaded(:final payouts, :final selectedPayoutId) =>
            Column(
              children: [
                if (demoMode) const _NoPaymentAccountBanner(),
                _PayoutsKpiRow(payouts: payouts),
                Expanded(
                  child: payouts.isEmpty
                      ? const NubiaEmptyState(
                          key: Key('cabinet_payouts_empty'),
                          icon: Icons.account_balance_outlined,
                          title: 'Aucun virement',
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final selectedPayout = selectedPayoutId == null
                                ? null
                                : payouts.firstWhere(
                                    (p) => p.id == selectedPayoutId,
                                  );
                            // Écran étroit (#5107) : le volet (400px fixe) ne
                            // laisserait presque plus de place au tableau —
                            // il remplace la liste plutôt que de la
                            // comprimer.
                            final narrow = constraints.maxWidth < 700;
                            if (narrow && selectedPayout != null) {
                              return _PayoutDetailPanel(payout: selectedPayout);
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _PayoutsList(
                                    payouts: payouts,
                                    selectedPayoutId: selectedPayoutId,
                                  ),
                                ),
                                if (selectedPayout != null)
                                  SizedBox(
                                    width: 400,
                                    child: _PayoutDetailPanel(
                                      payout: selectedPayout,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
        };
      },
    );
  }
}

/// Bandeau « aucun compte connecté » (design-v2, point 1) : remplace
/// l'ancienne note grise inline — porte l'avertissement et l'action
/// manquante (Connecter Stripe) là où il ne peut pas être confondu avec une
/// légende, et disparaît de lui-même une fois un compte relié.
class _NoPaymentAccountBanner extends StatelessWidget {
  const _NoPaymentAccountBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: const Key('cabinet_payouts_no_account_banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        border: Border(bottom: BorderSide(color: NubiaColors.warningBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: tokens.warningFg),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: textTheme.bodySmall?.copyWith(color: tokens.warningFg),
                children: const [
                  TextSpan(
                    text: 'Aucun compte de paiement connecté.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' Les virements affichés sont des données de '
                        "démonstration : rien n'est rapproché de vos "
                        'comptes réels.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          NubiaButton(
            key: const Key('cabinet_payouts_connect_stripe'),
            label: 'Connecter Stripe',
            variant: NubiaButtonVariant.secondary,
            size: NubiaButtonSize.sm,
            onPressed: () => NubiaSnackbar.show(
              context: context,
              message: 'Connexion Stripe à venir.',
            ),
          ),
        ],
      ),
    );
  }
}

/// Rangée de 4 compteurs KPI en tête d'écran (design-v2, point 4a) : reçu,
/// rapprochés, à vérifier, écart cumulé — calculés depuis `payouts`, jamais
/// en dur.
class _PayoutsKpiRow extends StatelessWidget {
  const _PayoutsKpiRow({required this.payouts});

  final List<CabinetPayout> payouts;

  @override
  Widget build(BuildContext context) {
    final receivedCents =
        payouts.fold<int>(0, (sum, payout) => sum + payout.amountCents);
    final reconciledCount = payouts
        .where((payout) =>
            payout.reconciliationStatus ==
            PayoutReconciliationStatus.reconciled)
        .length;
    final toVerifyPayouts = payouts.where(
      (payout) =>
          payout.reconciliationStatus == PayoutReconciliationStatus.toVerify,
    );
    final toVerifyCount = toVerifyPayouts.length;
    final cumulativeGapCents = toVerifyPayouts.fold<int>(
      0,
      (sum, payout) => sum + payout.differenceCents,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        key: const Key('cabinet_payouts_kpi_row'),
        children: [
          Expanded(
            child: _KpiTile(
              key: const Key('cabinet_payouts_kpi_received'),
              value: NubiaMoney.formatCents(receivedCents),
              label: 'virements reçus',
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _KpiTile(
              key: const Key('cabinet_payouts_kpi_reconciled'),
              value: '$reconciledCount',
              label: 'virements rapprochés',
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _KpiTile(
              key: const Key('cabinet_payouts_kpi_to_verify'),
              value: '$toVerifyCount',
              label: 'à vérifier',
              danger: true,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _KpiTile(
              key: const Key('cabinet_payouts_kpi_cumulative_gap'),
              value: NubiaMoney.formatCents(cumulativeGapCents),
              label: 'écart cumulé',
              danger: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compteur KPI compact (design-v2, point 4a) : valeur (18px, bold,
/// tabulaire) + libellé (10.5px, gris). Variante danger (classe `.kpi.d` de
/// la maquette) pour « à vérifier »/« écart cumulé ».
class _KpiTile extends StatelessWidget {
  const _KpiTile({
    super.key,
    required this.value,
    required this.label,
    this.danger = false,
  });

  final String value;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFeatures: tabularFigures,
            color: danger ? tokens.dangerFg : cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5, color: NubiaColors.n500),
        ),
      ],
    );
  }
}

/// Largeurs des colonnes du tableau des virements (design-v2, point 6) —
/// partagées entre [_PayoutsTableHeader] et [_PayoutTableRow] pour rester
/// alignées ; seule la colonne Virement est flexible.
class _PayoutColumns {
  const _PayoutColumns._();

  static const double gap = 16;
  static const double amountReceived = 112;
  static const double internalPayments = 132;
  static const double gapAmount = 92;
  static const double status = 116;
  static const double action = 100;
}

class _PayoutsList extends StatelessWidget {
  const _PayoutsList({required this.payouts, this.selectedPayoutId});

  final List<CabinetPayout> payouts;
  final String? selectedPayoutId;

  @override
  Widget build(BuildContext context) {
    final totalReceivedCents =
        payouts.fold<int>(0, (sum, payout) => sum + payout.amountCents);
    final cumulativeGapCents =
        payouts.fold<int>(0, (sum, payout) => sum + payout.differenceCents);
    return Column(
      key: const Key('cabinet_payouts_list'),
      children: [
        const _PayoutsTableHeader(),
        Expanded(
          child: ListView.builder(
            itemCount: payouts.length,
            itemBuilder: (context, index) {
              final payout = payouts[index];
              return _PayoutTableRow(
                payout: payout,
                selected: payout.id == selectedPayoutId,
              );
            },
          ),
        ),
        _PayoutsTableFooter(
          // Pas de filtrage dans cette liste : affiché == chargé, contrairement
          // au tableau Patients qui distingue résultats filtrés / total.
          displayedCount: payouts.length,
          totalCount: payouts.length,
          totalReceivedCents: totalReceivedCents,
          cumulativeGapCents: cumulativeGapCents,
        ),
      ],
    );
  }
}

/// En-tête de colonnes du tableau des virements (design-v2, point 6) : mots
/// exacts « Virement / Montant reçu / Paiements internes / Écart / Statut /
/// Action », alignées à droite pour les colonnes de chiffres et l'action.
class _PayoutsTableHeader extends StatelessWidget {
  const _PayoutsTableHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: tokens.textTertiary,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(child: Text('Virement', style: style)),
          const SizedBox(width: _PayoutColumns.gap),
          SizedBox(
            width: _PayoutColumns.amountReceived,
            child:
                Text('Montant reçu', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: _PayoutColumns.gap),
          SizedBox(
            width: _PayoutColumns.internalPayments,
            child: Text('Paiements internes',
                style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: _PayoutColumns.gap),
          SizedBox(
            width: _PayoutColumns.gapAmount,
            child: Text('Écart', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: _PayoutColumns.gap),
          SizedBox(
              width: _PayoutColumns.status,
              child: Text('Statut', style: style)),
          const SizedBox(width: _PayoutColumns.gap),
          SizedBox(
            width: _PayoutColumns.action,
            child: Text('Action', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// Ligne du tableau des virements (design-v2, point 6) : colonnes alignées
/// en chiffres tabulaires — seule disposition qui permette la lecture
/// verticale pour repérer l'anomalie (remplace les `NubiaCard` empilées).
class _PayoutTableRow extends StatelessWidget {
  const _PayoutTableRow({required this.payout, required this.selected});

  final CabinetPayout payout;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final reconciled =
        payout.reconciliationStatus == PayoutReconciliationStatus.reconciled;
    final gapCents = payout.differenceCents;
    final gapColor = gapCents == 0
        ? NubiaColors.n400
        : gapCents < 0
            ? NubiaColors.dangerFg
            : null;
    void onTap() => context
        .read<CabinetPayoutsBloc>()
        .add(CabinetPayoutSelected(payout.id));

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  _PayoutProviderPill(provider: payout.provider),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDate(payout.arrivalDate),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall
                              ?.copyWith(fontFeatures: tabularFigures),
                        ),
                        Text(
                          payout.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: NubiaColors.n500,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _PayoutColumns.gap),
            SizedBox(
              width: _PayoutColumns.amountReceived,
              child: Text(
                NubiaMoney.formatCents(payout.amountCents),
                textAlign: TextAlign.right,
                style: textTheme.bodyMedium
                    ?.copyWith(fontFeatures: tabularFigures),
              ),
            ),
            const SizedBox(width: _PayoutColumns.gap),
            SizedBox(
              width: _PayoutColumns.internalPayments,
              child: Text(
                NubiaMoney.formatCents(payout.internalPaymentsTotalCents),
                textAlign: TextAlign.right,
                style: textTheme.bodyMedium
                    ?.copyWith(fontFeatures: tabularFigures),
              ),
            ),
            const SizedBox(width: _PayoutColumns.gap),
            SizedBox(
              width: _PayoutColumns.gapAmount,
              child: Text(
                NubiaMoney.formatCents(gapCents),
                textAlign: TextAlign.right,
                style: textTheme.bodyMedium?.copyWith(
                  fontFeatures: tabularFigures,
                  fontWeight: gapCents == 0 ? FontWeight.w400 : FontWeight.w600,
                  color: gapColor,
                ),
              ),
            ),
            const SizedBox(width: _PayoutColumns.gap),
            SizedBox(
              width: _PayoutColumns.status,
              child: Align(
                alignment: Alignment.centerLeft,
                child: NubiaBadge.label(
                  key: const Key('payout_status_badge'),
                  label: reconciled ? 'Rapproché' : 'À vérifier',
                  variant: reconciled
                      ? NubiaBadgeVariant.success
                      : NubiaBadgeVariant.error,
                ),
              ),
            ),
            const SizedBox(width: _PayoutColumns.gap),
            SizedBox(
              width: _PayoutColumns.action,
              child: Align(
                alignment: Alignment.centerRight,
                child: reconciled
                    ? NubiaButton(
                        key: Key('payout_action_detail_${payout.id}'),
                        label: 'Détail',
                        variant: NubiaButtonVariant.secondary,
                        size: NubiaButtonSize.sm,
                        icon: Icons.visibility,
                        onPressed: onTap,
                      )
                    : NubiaButton(
                        key: Key('payout_action_analyze_${payout.id}'),
                        label: 'Analyser',
                        size: NubiaButtonSize.sm,
                        icon: Icons.search,
                        onPressed: onTap,
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
          key: Key('payout_${payout.id}'),
          color: selected ? NubiaColors.brand50 : Colors.transparent,
          // `foregroundDecoration` (pas `decoration`) : peint la bordure
          // par-dessus le contenu sans lui ajouter de padding implicite,
          // pour ne pas décaler les colonnes fixes du tableau.
          foregroundDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? NubiaColors.brand700 : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: content),
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
      ],
    );
  }
}

/// Pied de tableau (design-v2, point 6) : compteur de virements affichés,
/// total reçu et écart cumulé sur les lignes affichées.
class _PayoutsTableFooter extends StatelessWidget {
  const _PayoutsTableFooter({
    required this.displayedCount,
    required this.totalCount,
    required this.totalReceivedCents,
    required this.cumulativeGapCents,
  });

  final int displayedCount;
  final int totalCount;
  final int totalReceivedCents;
  final int cumulativeGapCents;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          '$displayedCount virements affichés sur $totalCount · '
          'Total reçu ${NubiaMoney.formatCents(totalReceivedCents)} · '
          'Écart cumulé ${NubiaMoney.formatCents(cumulativeGapCents)}',
          key: const Key('cabinet_payouts_footer'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textTertiary,
                fontFeatures: tabularFigures,
              ),
        ),
      ),
    );
  }
}

/// Pastille provider (design-v2, point 5) : `STR`/`GCL` — identifie le
/// prestataire d'un coup d'œil, la date reste l'information principale de
/// la cellule (#5103).
class _PayoutProviderPill extends StatelessWidget {
  const _PayoutProviderPill({required this.provider});

  final PayoutProvider provider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: NubiaColors.n100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: NubiaColors.n200),
      ),
      child: Text(
        _providerCode(provider),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: NubiaColors.n600,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Squelette de chargement (design-v2, #5105) : calque la grille du tableau
/// de virements (lignes fantômes) plutôt qu'un spinner centré.
class _CabinetPayoutsSkeleton extends StatelessWidget {
  const _CabinetPayoutsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('cabinet_payouts_loading'),
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 4; i++) ...[
          const _CabinetPayoutRowSkeleton(),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CabinetPayoutRowSkeleton extends StatelessWidget {
  const _CabinetPayoutRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(child: NubiaSkeletonLoader(height: 16, width: 160)),
              SizedBox(width: 8),
              NubiaSkeletonLoader(
                height: 20,
                width: 72,
                borderRadius: 999,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const NubiaSkeletonLoader(height: 12, width: 120),
          const SizedBox(height: 4),
          const NubiaSkeletonLoader(height: 12, width: 180),
          const SizedBox(height: 4),
          const NubiaSkeletonLoader(height: 12, width: 150),
        ],
      ),
    );
  }
}

/// Volet de détail d'un virement sélectionné — pied de volet : deux actions
/// de résolution de l'écart (#5111), marquer rapproché ou signaler au
/// comptable.
class _PayoutDetailPanel extends StatelessWidget {
  const _PayoutDetailPanel({required this.payout});

  final CabinetPayout payout;

  @override
  Widget build(BuildContext context) {
    final reconciled =
        payout.reconciliationStatus == PayoutReconciliationStatus.reconciled;
    final probableLead = _probableLead(payout);
    return DecoratedBox(
      key: const Key('payout_detail_panel'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: Theme.of(context).extension<NubiaTokens>()!.borderSubtle,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Virement du ${_shortDate(payout.arrivalDate)} · '
                    '${_providerLabel(payout.provider)}',
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: const Key('payout_detail_close'),
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close),
                  onPressed: () => context
                      .read<CabinetPayoutsBloc>()
                      .add(CabinetPayoutSelected(payout.id)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PayoutComparisonRow(payout: payout),
                    if (!reconciled) ...[
                      const SizedBox(height: 12),
                      _PayoutGapCard(payout: payout),
                    ],
                    if (probableLead != null) ...[
                      const SizedBox(height: 12),
                      _ProbableLeadCard(payout: payout, lead: probableLead),
                    ],
                    if (payout.internalPayments.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _InternalPaymentsSection(
                        payments: payout.internalPayments,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            NubiaButton(
              key: const Key('payout_action_flag_accountant'),
              label: 'Signaler au comptable',
              variant: NubiaButtonVariant.secondary,
              onPressed: () {
                context
                    .read<CabinetPayoutsBloc>()
                    .add(CabinetPayoutFlaggedToAccountant(payout.id));
                NubiaSnackbar.show(
                  context: context,
                  message: 'Signalé au comptable.',
                );
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: NubiaButton(
                key: const Key('payout_action_mark_reconciled'),
                label: 'Marquer comme rapproché',
                icon: Icons.check,
                onPressed: () => context
                    .read<CabinetPayoutsBloc>()
                    .add(CabinetPayoutMarkedReconciled(payout.id)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Comparaison « Reçu en banque » vs « Encaissé au cabinet » (#5108) : deux
/// blocs côte à côte, pour matérialiser le rapprochement comme une
/// comparaison de deux nombres plutôt que des phrases.
class _PayoutComparisonRow extends StatelessWidget {
  const _PayoutComparisonRow({required this.payout});

  final CabinetPayout payout;

  @override
  Widget build(BuildContext context) {
    final internalPaymentsCount = payout.internalPayments.length;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ComparisonTile(
              key: const Key('payout_comparison_bank'),
              icon: Icons.account_balance,
              title: 'Reçu en banque',
              value: NubiaMoney.formatCents(payout.amountCents),
              subtitle: 'arrivé le ${_shortDate(payout.arrivalDate)}',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ComparisonTile(
              key: const Key('payout_comparison_cabinet'),
              icon: Icons.receipt_long,
              title: 'Encaissé au cabinet',
              value: NubiaMoney.formatCents(payout.internalPaymentsTotalCents),
              subtitle: '$internalPaymentsCount '
                  '${internalPaymentsCount > 1 ? 'paiements' : 'paiement'} '
                  'du ${_shortDate(payout.arrivalDate)}',
            ),
          ),
        ],
      ),
    );
  }
}

/// Tuile compacte icône + valeur + sous-ligne, pour les deux blocs du
/// rapprochement (variante de `MetricTile` avec sous-ligne).
class _ComparisonTile extends StatelessWidget {
  const _ComparisonTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style:
                      textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(
              color: cs.onSurface,
              fontFeatures: tabularFigures,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Encart d'écart (#5108) : montant en valeur absolue + sens (quel côté a
/// reçu le plus), remplace l'ancienne ligne « Écart : X € » sans indication
/// de sens.
class _PayoutGapCard extends StatelessWidget {
  const _PayoutGapCard({required this.payout});

  final CabinetPayout payout;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('payout_reconciliation_gap'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.dangerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NubiaColors.dangerBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error, size: 18, color: tokens.dangerFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: textTheme.bodySmall?.copyWith(color: tokens.dangerFg),
                children: [
                  const TextSpan(text: 'Écart de '),
                  TextSpan(
                    text: NubiaMoney.formatCents(payout.differenceCents.abs()),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: ' — ${_gapSensePhrase(payout.differenceCents)}',
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

/// Encart « Piste probable » (#5110) : signale un paiement non rapprochable
/// par le prestataire (espèces, chèque…) dont le montant égale exactement
/// l'écart. Purement indicatif — aucun rapprochement automatique, la
/// décision reste humaine (boutons du pied de volet, #5111).
class _ProbableLeadCard extends StatelessWidget {
  const _ProbableLeadCard({required this.payout, required this.lead});

  final CabinetPayout payout;
  final InternalPayment lead;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('payout_probable_lead'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NubiaColors.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 18, color: tokens.warningFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: textTheme.bodySmall?.copyWith(color: tokens.warningFg),
                children: [
                  const TextSpan(
                    text: 'Piste probable : ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: 'le paiement en ${lead.methodLabel} de '
                        '${NubiaMoney.formatCents(lead.amountCents)} ne '
                        'transite pas par ${_providerLabel(payout.provider)} '
                        "— il explique exactement l'écart. À rapprocher de "
                        'la caisse, pas du virement.',
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

/// Liste « Paiements internes du jour » (#5109) : chaque encaissement
/// interne du jour, en signalant ceux qui ne transitent pas par le
/// prestataire (espèces/chèque). Purement informatif — aucun rapprochement
/// automatique, données et ordre proviennent tels quels du domaine.
class _InternalPaymentsSection extends StatelessWidget {
  const _InternalPaymentsSection({required this.payments});

  final List<InternalPayment> payments;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: const Key('payout_internal_payments_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Paiements internes du jour',
                style: textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            NubiaBadge.count(
              key: const Key('payout_internal_payments_count'),
              count: payments.length,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final payment in payments) ...[
          _InternalPaymentRow(payment: payment),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _InternalPaymentRow extends StatelessWidget {
  const _InternalPaymentRow({required this.payment});

  final InternalPayment payment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NubiaAvatar(initials: _initials(payment.patientName), radius: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payment.patientName,
                style: textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${payment.methodLabel} · ${payment.time}',
                style: textTheme.bodySmall?.copyWith(color: mutedColor),
              ),
              if (!payment.reconcilableByProvider)
                Text(
                  'non rapprochable',
                  style: textTheme.bodySmall?.copyWith(color: mutedColor),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          NubiaMoney.formatCents(payment.amountCents),
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

/// Initiales (ex. « Camille Moreau » → « CM ») — même règle que
/// `patients_page.dart::_initials`.
String _initials(String fullName) {
  final parts =
      fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
