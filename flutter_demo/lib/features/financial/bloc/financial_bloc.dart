import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/financial_repository.dart';
import '../services/payment_service.dart';
import 'financial_event.dart';
import 'financial_state.dart';

class FinancialBloc extends Bloc<FinancialEvent, FinancialState> {
  FinancialBloc({
    required FinancialRepository repository,
    required PaymentService paymentService,
  })  : _repository = repository,
        _paymentService = paymentService,
        super(const FinancialInitial()) {
    on<FinancialLoadRequested>(_onLoadRequested);
    on<FinancialPaymentRequested>(_onPaymentRequested);
  }

  final FinancialRepository _repository;
  final PaymentService _paymentService;

  Future<void> _onLoadRequested(
    FinancialLoadRequested event,
    Emitter<FinancialState> emit,
  ) async {
    emit(const FinancialLoading());
    try {
      final summary = await _repository.fetchSummary(event.patientId);
      emit(FinancialLoaded(summary));
    } catch (e) {
      emit(FinancialError(e.toString()));
    }
  }

  Future<void> _onPaymentRequested(
    FinancialPaymentRequested event,
    Emitter<FinancialState> emit,
  ) async {
    final currentState = state;
    if (currentState is! FinancialLoaded) return;

    emit(FinancialPaymentInProgress(currentState.summary));
    try {
      await _paymentService.presentPaymentSheet(
        amountCents: event.amountCents,
        milestoneId: event.milestoneId,
      );
      // Recharge le résumé après paiement.
      final updated = await _repository.fetchSummary(event.patientId);
      emit(FinancialLoaded(updated));
    } catch (e) {
      emit(FinancialError(e.toString()));
    }
  }
}
