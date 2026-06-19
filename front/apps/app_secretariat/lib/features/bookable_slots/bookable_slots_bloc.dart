import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'bookable_slots_event.dart';
import 'bookable_slots_state.dart';

class BookableSlotsBloc
    extends Bloc<BookableSlotsEvent, BookableSlotsState> {
  final ListBookableSlotsUseCase _listSlots;

  BookableSlotsBloc({required ListBookableSlotsUseCase listSlots})
      : _listSlots = listSlots,
        super(const BookableSlotsInitial()) {
    on<BookableSlotsLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    BookableSlotsLoadRequested event,
    Emitter<BookableSlotsState> emit,
  ) async {
    emit(const BookableSlotsLoading());
    final result = await _listSlots();
    result.fold(
      (failure) => emit(BookableSlotsError(failure.message)),
      (slots) => emit(BookableSlotsLoaded(slots)),
    );
  }
}
