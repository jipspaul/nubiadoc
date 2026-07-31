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
}
