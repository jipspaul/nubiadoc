import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'appointments_event.dart';
import 'appointments_state.dart';

class AppointmentsBloc extends Bloc<AppointmentsEvent, AppointmentsState>
    with SafeEmitMixin<AppointmentsState> {
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
    on<AppointmentsSearchChanged>(_onSearchChanged, transformer: restartable());
    on<AppointmentsProviderSelected>(_onProviderSelected, transformer: droppable());
    on<AppointmentsSlotSelected>(_onSlotSelected, transformer: droppable());
    on<AppointmentsMotifChanged>(_onMotifChanged);
    on<AppointmentsBookingConfirmed>(_onBookingConfirmed, transformer: droppable());
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
    try {
      final result = await _searchProviders(query: query);
      result.fold(
        (failure) => safeEmit(AppointmentsError(failure.message)),
        (providers) => safeEmit(AppointmentsProvidersLoaded(
          providers: providers,
          query: query,
        )),
      );
    } catch (_) {
      safeEmit(const AppointmentsError('Erreur de recherche.'));
    }
  }

  Future<void> _onProviderSelected(
    AppointmentsProviderSelected event,
    Emitter<AppointmentsState> emit,
  ) async {
    emit(AppointmentsSlotsLoading(event.provider));
    try {
      final result = await _searchSlots(providerId: event.provider.id);
      result.fold(
        (failure) => safeEmit(AppointmentsError(failure.message)),
        (slots) => safeEmit(AppointmentsSlotsLoaded(
          provider: event.provider,
          slots: slots,
        )),
      );
    } catch (_) {
      safeEmit(const AppointmentsError('Erreur de chargement des créneaux.'));
    }
  }

  Future<void> _onSlotSelected(
    AppointmentsSlotSelected event,
    Emitter<AppointmentsState> emit,
  ) async {
    final current = state;
    if (current is! AppointmentsSlotsLoaded) return;
    if (!event.slot.isAvailable) return;

    try {
      final holdResult = await _holdSlot(event.slot.id);
      holdResult.fold(
        (failure) => safeEmit(AppointmentsError(failure.message)),
        (_) => safeEmit(current.copyWith(selectedSlot: event.slot)),
      );
    } catch (_) {
      safeEmit(const AppointmentsError('Erreur lors de la sélection du créneau.'));
    }
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
    try {
      final result = await _bookAppointment(
        slotId: slot.id,
        motif: current.motif.trim(),
      );
      result.fold(
        (failure) => safeEmit(AppointmentsError(failure.message)),
        (appointment) => safeEmit(AppointmentsBookingSuccess(appointment)),
      );
    } catch (_) {
      safeEmit(const AppointmentsError('Erreur lors de la réservation.'));
    }
  }
}
