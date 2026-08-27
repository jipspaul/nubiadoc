import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cabinet_payouts_event.dart';
import 'cabinet_payouts_state.dart';

/// Rapprochement virements Stripe/GoCardless (#4129) :
/// `GET /v1/cabinet/payouts` (mock côté back, cf. docstring de
/// `cabinet_payouts.rs`) rapproché aux paiements internes du cabinet.
class CabinetPayoutsBloc extends Bloc<CabinetPayoutsEvent, CabinetPayoutsState>
    with SafeEmitMixin<CabinetPayoutsState> {
  CabinetPayoutsBloc({
    required GetCabinetPayoutsUseCase getPayouts,
    required MarkPayoutReconciledUseCase markReconciled,
    required FlagPayoutToAccountantUseCase flagToAccountant,
  })  : _getPayouts = getPayouts,
        _markReconciled = markReconciled,
        _flagToAccountant = flagToAccountant,
        super(const CabinetPayoutsLoading()) {
    on<CabinetPayoutsLoadRequested>(_onLoad);
    on<CabinetPayoutSelected>(_onSelected);
    on<CabinetPayoutMarkedReconciled>(_onMarkedReconciled);
    on<CabinetPayoutFlaggedToAccountant>(_onFlaggedToAccountant);
    on<CabinetPayoutsMonthChanged>(_onMonthChanged);
  }

  final GetCabinetPayoutsUseCase _getPayouts;
  final MarkPayoutReconciledUseCase _markReconciled;
  final FlagPayoutToAccountantUseCase _flagToAccountant;

  /// Mois affiché par le sélecteur d'en-tête (design-v2, point 4b) — mois
  /// courant par défaut, premier jour du mois (jour/heure ignorés).
  DateTime _selectedMonth = _startOfMonth(DateTime.now());

  static DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month);

  Future<void> _onLoad(
    CabinetPayoutsLoadRequested event,
    Emitter<CabinetPayoutsState> emit,
  ) async {
    emit(const CabinetPayoutsLoading());
    final result = await _getPayouts();
    result.fold(
      (failure) => safeEmit(CabinetPayoutsError(failure.message)),
      (payouts) => safeEmit(
        CabinetPayoutsLoaded(
          _filterByMonth(payouts),
          selectedMonth: _selectedMonth,
        ),
      ),
    );
  }

  Future<void> _onMonthChanged(
    CabinetPayoutsMonthChanged event,
    Emitter<CabinetPayoutsState> emit,
  ) async {
    _selectedMonth = _startOfMonth(event.month);
    await _onLoad(const CabinetPayoutsLoadRequested(), emit);
  }

  List<CabinetPayout> _filterByMonth(List<CabinetPayout> payouts) => [
        for (final payout in payouts)
          if (payout.arrivalDate.year == _selectedMonth.year &&
              payout.arrivalDate.month == _selectedMonth.month)
            payout,
      ];

  void _onSelected(
    CabinetPayoutSelected event,
    Emitter<CabinetPayoutsState> emit,
  ) {
    final current = state;
    if (current is! CabinetPayoutsLoaded) return;
    final alreadySelected = current.selectedPayoutId == event.id;
    safeEmit(
      CabinetPayoutsLoaded(
        current.payouts,
        selectedPayoutId: alreadySelected ? null : event.id,
        selectedMonth: current.selectedMonth,
      ),
    );
  }

  /// Marque le virement comme rapproché — décision humaine déclenchée par
  /// l'action, jamais automatique. Persisté côté back (#5969) : l'état
  /// local n'est mis à jour qu'une fois le serveur confirmé, pour ne
  /// jamais afficher un badge "rapproché" que le prochain refresh
  /// annulerait. `reconciliationStatus` reste le seul pilote du badge.
  Future<void> _onMarkedReconciled(
    CabinetPayoutMarkedReconciled event,
    Emitter<CabinetPayoutsState> emit,
  ) async {
    final current = state;
    if (current is! CabinetPayoutsLoaded) return;
    final result = await _markReconciled(event.id);
    result.fold((failure) {}, (_) {
      final latest = state;
      if (latest is! CabinetPayoutsLoaded) return;
      safeEmit(
        CabinetPayoutsLoaded(
          [
            for (final payout in latest.payouts)
              if (payout.id == event.id) _reconciled(payout) else payout,
          ],
          selectedPayoutId: latest.selectedPayoutId,
          selectedMonth: latest.selectedMonth,
        ),
      );
    });
  }

  /// Signale l'écart au comptable (#5969) : appel réseau réel, désormais
  /// tracé côté back — remplace l'ancien handler no-op. Aucun état métier
  /// dédié côté virement, le feedback reste porté par l'UI (snackbar).
  Future<void> _onFlaggedToAccountant(
    CabinetPayoutFlaggedToAccountant event,
    Emitter<CabinetPayoutsState> emit,
  ) async {
    await _flagToAccountant(event.id);
  }

  /// Copie le payout avec le statut rapproché (le domaine n'expose pas de
  /// `copyWith`).
  CabinetPayout _reconciled(CabinetPayout payout) => CabinetPayout(
        id: payout.id,
        provider: payout.provider,
        amountCents: payout.amountCents,
        currency: payout.currency,
        arrivalDate: payout.arrivalDate,
        reconciliationStatus: PayoutReconciliationStatus.reconciled,
        internalPaymentsTotalCents: payout.internalPaymentsTotalCents,
        internalPayments: payout.internalPayments,
      );
}
