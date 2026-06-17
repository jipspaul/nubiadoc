import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'appointments_event.dart';
import 'appointments_state.dart';

class AppointmentsBloc extends Bloc<AppointmentsEvent, AppointmentsState> {
  final SearchProvidersUseCase _searchProviders;
  final SearchSlotsUseCase _searchSlots;
  final HoldSlotUseCase _holdSlot;
  final BookAppointmentUseCase _bookAppointment;

  AppointmentsBloc({
    required SearchProvidersUseCase searchProviders,
    required SearchSlotsUseCase searchSlots,
    required HoldSlotUseCase holdSlot,
    required BookAppointmentUseCase bookAppointment,
  })  : _searchProviders = searchProviders,
        _searchSlots = searchSlots,
        _holdSlot = holdSlot,
        _bookAppointment = bookAppointment,
        super(const AppointmentsInitial()) {
    on<AppointmentsSearchChanged>(_onSearchChanged);
    on<AppointmentsProviderSelected>(_onProviderSelected);
    on<AppointmentsSlotSelected>(_onSlotSelected);
    on<AppointmentsMotifChanged>(_onMotifChanged);
    on<AppointmentsBookingConfirmed>(_onBookingConfirmed);
  }

  Future<void> _onSearchChanged(
    AppointmentsSearchChanged event,
    Emitter<AppointmentsState> emit,
  ) async {
    final query = event.query.trim();
    if (query.isEmpty) {
      emit(const AppointmentsInitial());
      return;
    }
    emit(const AppointmentsSearchLoading());
    final result = await _searchProviders(query: query);
    result.fold(
      (failure) => emit(AppointmentsError(failure.message)),
      (providers) => emit(AppointmentsProvidersLoaded(
        providers: providers,
        query: query,
      )),
    );
  }

  Future<void> _onProviderSelected(
    AppointmentsProviderSelected event,
    Emitter<AppointmentsState> emit,
  ) async {
    emit(AppointmentsSlotsLoading(event.provider));
    final result = await _searchSlots(providerId: event.provider.id);
    result.fold(
      (failure) => emit(AppointmentsError(failure.message)),
      (slots) => emit(AppointmentsSlotsLoaded(
        provider: event.provider,
        slots: slots,
      )),
    );
  }

  Future<void> _onSlotSelected(
    AppointmentsSlotSelected event,
    Emitter<AppointmentsState> emit,
  ) async {
    final current = state;
    if (current is! AppointmentsSlotsLoaded) return;
    if (!event.slot.isAvailable) return;

    final holdResult = await _holdSlot(event.slot.id);
    holdResult.fold(
      (failure) => emit(AppointmentsError(failure.message)),
      (_) => emit(current.copyWith(selectedSlot: event.slot)),
    );
  }

  void _onMotifChanged(
    AppointmentsMotifChanged event,
    Emitter<AppointmentsState> emit,
  ) {
    final current = state;
    if (current is! AppointmentsSlotsLoaded) return;
    emit(current.copyWith(motif: event.motif));
  }

  Future<void> _onBookingConfirmed(
    AppointmentsBookingConfirmed event,
    Emitter<AppointmentsState> emit,
  ) async {
    final current = state;
    if (current is! AppointmentsSlotsLoaded) return;
    final slot = current.selectedSlot;
    if (slot == null || current.motif.trim().isEmpty) return;

    emit(const AppointmentsBookingLoading());
    final result = await _bookAppointment(
      slotId: slot.id,
      motif: current.motif.trim(),
    );
    result.fold(
      (failure) => emit(AppointmentsError(failure.message)),
      (appointment) => emit(AppointmentsBookingSuccess(appointment)),
    );
  }
}
