import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_event.dart';
import 'devis_state.dart';

class DevisBloc extends Bloc<DevisEvent, DevisState>
    with SafeEmitMixin<DevisState> {
  final ListCabinetQuotesUseCase _list;
  final GetCabinetQuoteUseCase _getById;

  DevisBloc({
    required ListCabinetQuotesUseCase listQuotes,
    required GetCabinetQuoteUseCase getQuote,
  })  : _list = listQuotes,
        _getById = getQuote,
        super(const DevisInitial()) {
    on<DevisLoadRequested>(_onLoad);
    on<DevisDetailLoadRequested>(_onDetailLoad);
  }

  Future<void> _onLoad(
    DevisLoadRequested event,
    Emitter<DevisState> emit,
  ) async {
    emit(const DevisLoading());
    try {
      final result = await _list();
      result.fold(
        (failure) => safeEmit(DevisError(failure.message)),
        (quotes) => safeEmit(DevisLoaded(quotes)),
      );
    } catch (_) {
      safeEmit(const DevisError('Erreur de chargement.'));
    }
  }

  Future<void> _onDetailLoad(
    DevisDetailLoadRequested event,
    Emitter<DevisState> emit,
  ) async {
    emit(const DevisLoading());
    try {
      final result = await _getById(event.id);
      result.fold(
        (failure) => safeEmit(DevisDetailError(failure.message)),
        (quote) => safeEmit(DevisDetailLoaded(quote)),
      );
    } catch (_) {
      safeEmit(const DevisDetailError('Erreur de chargement.'));
    }
  }
}
