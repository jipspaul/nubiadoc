import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'appointments_event.dart';
import 'appointments_state.dart';

class AppointmentsBloc extends Bloc<AppointmentsEvent, AppointmentsState>
    with SafeEmitMixin<AppointmentsState> {
  final SearchProvidersUseCase _searchProviders;
  final SearchSlotsUseCase _searchSlots;
  final HoldSlotUseCase _holdSlot;
  final ConfirmBookingUseCase _confirmBooking;

  // Dernière liste de praticiens affichée, pour revenir en arrière depuis les
  // créneaux sans refaire d'appel réseau.
  AppointmentsProvidersLoaded _lastProvidersLoaded =
      const AppointmentsProvidersLoaded(providers: [], query: '');

  AppointmentsBloc({
    required SearchProvidersUseCase searchProviders,
    required SearchSlotsUseCase searchSlots,
    required HoldSlotUseCase holdSlot,
    required ConfirmBookingUseCase confirmBooking,
  })  : _searchProviders = searchProviders,
        _searchSlots = searchSlots,
        _holdSlot = holdSlot,
        _confirmBooking = confirmBooking,
        super(const AppointmentsInitial()) {
    on<AppointmentsSearchChanged>(_onSearchChanged, transformer: restartable());
    on<AppointmentsProviderSelected>(_onProviderSelected,
        transformer: droppable());
    on<AppointmentsSlotSelected>(_onSlotSelected, transformer: droppable());
    on<AppointmentsMotifChanged>(_onMotifChanged);
    on<AppointmentsBookingConfirmed>(_onBookingConfirmed,
        transformer: droppable());
    on<AppointmentsHoldExpired>(_onHoldExpired, transformer: droppable());
    on<AppointmentsBackToSearch>(_onBackToSearch, transformer: droppable());
  }

  Future<void> _onSearchChanged(
    AppointmentsSearchChanged event,
    Emitter<AppointmentsState> emit,
  ) async {
    final query = event.query.trim();
    // Requête vide = annuaire par défaut : on affiche quand même des résultats
    // (l'API renvoie les praticiens listés). L'écran n'est jamais vide au départ.
    emit(const AppointmentsSearchLoading());
    try {
      final result = await _searchProviders(query: query);
      result.fold(
        (failure) => emit(AppointmentsError(failure.message)),
        (providers) {
          _lastProvidersLoaded = AppointmentsProvidersLoaded(
            providers: providers,
            query: query,
          );
          emit(_lastProvidersLoaded);
        },
      );
    } catch (_) {
      emit(const AppointmentsError('Erreur de recherche.'));
    }
  }

  void _onBackToSearch(
    AppointmentsBackToSearch event,
    Emitter<AppointmentsState> emit,
  ) {
    // Retour instantané à la dernière liste de praticiens connue, sans
    // refaire d'appel réseau.
    emit(_lastProvidersLoaded);
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
        (hold) => safeEmit(current.copyWith(
          selectedSlot: event.slot,
          holdToken: hold.token,
          holdExpiresAt: hold.expiresAt,
        )),
      );
    } catch (_) {
      safeEmit(
          const AppointmentsError('Erreur lors de la sélection du créneau.'));
    }
  }

  // #5363 : le décompte du récapitulatif (UI) arrive à zéro — le hold n'est
  // plus valide, on relâche la sélection pour que le créneau redevienne
  // choisissable (l'utilisateur en est informé via un SnackBar côté UI).
  void _onHoldExpired(
    AppointmentsHoldExpired event,
    Emitter<AppointmentsState> emit,
  ) {
    final current = state;
    if (current is! AppointmentsSlotsLoaded) return;
    emit(current.copyWith(clearSelectedSlot: true));
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
    final holdToken = current.holdToken;
    if (slot == null || holdToken == null || current.motif.trim().isEmpty) {
      return;
    }
    final motif = current.motif.trim();

    emit(const AppointmentsBookingLoading());
    try {
      final result = await _confirmBooking(
        slotId: slot.id,
        holdToken: holdToken,
        motif: motif,
        idempotencyKey: '${slot.id}-booking-$holdToken',
      );
      result.fold(
        (failure) => safeEmit(AppointmentsError(failure.message)),
        (appointmentId) => safeEmit(AppointmentsBookingSuccess(Appointment(
          id: appointmentId,
          cabinetId: slot.cabinetId,
          practitionerName: current.provider.displayName,
          practitionerSpecialty: current.provider.specialty,
          startsAt: slot.startsAt,
          duration: slot.duration,
          motif: motif,
          status: AppointmentStatus.requested,
        ))),
      );
    } catch (_) {
      safeEmit(const AppointmentsError('Erreur lors de la réservation.'));
    }
  }
}
