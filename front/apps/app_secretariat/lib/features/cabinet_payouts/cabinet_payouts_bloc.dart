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
  CabinetPayoutsBloc({required GetCabinetPayoutsUseCase getPayouts})
      : _getPayouts = getPayouts,
        super(const CabinetPayoutsLoading()) {
    on<CabinetPayoutsLoadRequested>(_onLoad);
    on<CabinetPayoutSelected>(_onSelected);
    on<CabinetPayoutMarkedReconciled>(_onMarkedReconciled);
    on<CabinetPayoutFlaggedToAccountant>(_onFlaggedToAccountant);
  }

  final GetCabinetPayoutsUseCase _getPayouts;

  Future<void> _onLoad(
    CabinetPayoutsLoadRequested event,
    Emitter<CabinetPayoutsState> emit,
  ) async {
    emit(const CabinetPayoutsLoading());
    final result = await _getPayouts();
    result.fold(
      (failure) => safeEmit(CabinetPayoutsError(failure.message)),
      (payouts) => safeEmit(CabinetPayoutsLoaded(payouts)),
    );
  }

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
      ),
    );
  }

  /// Marque le virement comme rapproché — décision humaine déclenchée par
  /// l'action, jamais automatique. `reconciliationStatus` reste le seul
  /// pilote du badge.
  void _onMarkedReconciled(
    CabinetPayoutMarkedReconciled event,
    Emitter<CabinetPayoutsState> emit,
  ) {
    final current = state;
    if (current is! CabinetPayoutsLoaded) return;
    safeEmit(
      CabinetPayoutsLoaded(
        [
          for (final payout in current.payouts)
            if (payout.id == event.id) _reconciled(payout) else payout,
        ],
        selectedPayoutId: current.selectedPayoutId,
      ),
    );
  }

  /// Signale l'écart au comptable : aucun état métier dédié côté virement,
  /// le feedback est porté par l'UI (snackbar).
  void _onFlaggedToAccountant(
    CabinetPayoutFlaggedToAccountant event,
    Emitter<CabinetPayoutsState> emit,
  ) {}

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
