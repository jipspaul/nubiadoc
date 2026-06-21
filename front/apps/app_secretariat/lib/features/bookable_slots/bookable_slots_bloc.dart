import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'bookable_slots_event.dart';
import 'bookable_slots_state.dart';

class BookableSlotsBloc extends Bloc<BookableSlotsEvent, BookableSlotsState> {
  final ListBookableSlotsUseCase _listSlots;
  final CreateSlotUseCase _createSlot;

  BookableSlotsBloc({
    required ListBookableSlotsUseCase listSlots,
    required CreateSlotUseCase createSlot,
  })  : _listSlots = listSlots,
        _createSlot = createSlot,
        super(const BookableSlotsInitial()) {
    on<BookableSlotsLoadRequested>(_onLoad);
    on<CreateSlotRequested>(_onCreate);
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

  Future<void> _onCreate(
    CreateSlotRequested event,
    Emitter<BookableSlotsState> emit,
  ) async {
    emit(const BookableSlotsLoading());
    final result = await _createSlot(
      cabinetId: '',
      practitionerId: '',
      start: event.startsAt,
      duration: event.endsAt.difference(event.startsAt),
    );
    result.fold(
      (failure) => emit(BookableSlotsError(failure.message)),
      (_) => add(const BookableSlotsLoadRequested()),
    );
  }
}
