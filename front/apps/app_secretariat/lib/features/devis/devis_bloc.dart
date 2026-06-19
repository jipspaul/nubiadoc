import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_event.dart';
import 'devis_state.dart';

class DevisBloc extends Bloc<DevisEvent, DevisState> {
  final ListCabinetQuotesUseCase _list;

  DevisBloc({required ListCabinetQuotesUseCase listQuotes})
      : _list = listQuotes,
        super(const DevisInitial()) {
    on<DevisLoadRequested>(_onLoad);
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
}
