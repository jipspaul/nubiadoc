import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'bookable_slots_event.dart';
import 'bookable_slots_state.dart';

class BookableSlotsBloc extends Bloc<BookableSlotsEvent, BookableSlotsState>
    with SafeEmitMixin<BookableSlotsState> {
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
    try {
      final result = await _listSlots();
      result.fold(
        (failure) => safeEmit(BookableSlotsError(failure.message)),
        (slots) => safeEmit(BookableSlotsLoaded(slots)),
      );
    } catch (_) {
      safeEmit(const BookableSlotsError('Erreur de chargement.'));
    }
  }

  Future<void> _onCreate(
    CreateSlotRequested event,
    Emitter<BookableSlotsState> emit,
  ) async {
    emit(const BookableSlotsLoading());
    try {
      final result = await _createSlot(
        cabinetId: '',
        practitionerId: '',
        start: event.startsAt,
        duration: event.endsAt.difference(event.startsAt),
      );
      result.fold(
        (failure) => safeEmit(BookableSlotsError(failure.message)),
        (_) => add(const BookableSlotsLoadRequested()),
      );
    } catch (_) {
      safeEmit(const BookableSlotsError('Erreur de chargement.'));
    }
  }
}
