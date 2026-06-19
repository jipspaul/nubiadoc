import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_event.dart';
import 'devis_state.dart';

class DevisBloc extends Bloc<DevisEvent, DevisState> {
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
    final result = await _list();
    result.fold(
      (failure) => emit(DevisError(failure.message)),
      (quotes) => emit(DevisLoaded(quotes)),
    );
  }

  Future<void> _onDetailLoad(
    DevisDetailLoadRequested event,
    Emitter<DevisState> emit,
  ) async {
    emit(const DevisLoading());
    final result = await _getById(event.id);
    result.fold(
      (failure) => emit(DevisDetailError(failure.message)),
      (quote) => emit(DevisDetailLoaded(quote)),
    );
  }
}
