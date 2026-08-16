import 'dart:math';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../session/auth_cubit.dart';
import 'appointments_event.dart';
import 'appointments_state.dart';

const _kGuestCguVersion = '1.0';

/// Mot de passe temporaire généré côté client pour le compte créé à la
/// confirmation (#5362) : la maquette demande explicitement de ne PAS
/// solliciter de mot de passe à ce stade (« Un mot de passe vous sera
/// demandé après confirmation »). Le patient définira le sien ensuite via
/// le parcours mot de passe oublié (email), comme un compte existant qui
/// aurait perdu son mot de passe — aucune valeur n'est donc affichée ni
/// stockée côté UI.
String _generateGuestPassword() {
  final rng = Random.secure();
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  final body =
      List.generate(20, (_) => chars[rng.nextInt(chars.length)]).join();
  // Garantit au moins un chiffre (validation backend : 8+ caractères + 1 chiffre).
  return '$body${rng.nextInt(10)}';
}

class AppointmentsBloc extends Bloc<AppointmentsEvent, AppointmentsState>
    with SafeEmitMixin<AppointmentsState> {
  final SearchProvidersUseCase _searchProviders;
  final SearchSlotsUseCase _searchSlots;
  final HoldSlotUseCase _holdSlot;
  final ConfirmBookingUseCase _confirmBooking;
  final RegisterUseCase _register;
  final UpdateAccountUseCase _updateAccount;
  final UpdateNotificationPreferencesUseCase _updateNotificationPreferences;
  final AuthCubit _authCubit;

  // Dernière liste de praticiens affichée, pour revenir en arrière depuis les
  // créneaux sans refaire d'appel réseau.
  AppointmentsProvidersLoaded _lastProvidersLoaded =
      const AppointmentsProvidersLoaded(providers: [], query: '');

  AppointmentsBloc({
    required SearchProvidersUseCase searchProviders,
    required SearchSlotsUseCase searchSlots,
    required HoldSlotUseCase holdSlot,
    required ConfirmBookingUseCase confirmBooking,
    required RegisterUseCase register,
    required UpdateAccountUseCase updateAccount,
    required UpdateNotificationPreferencesUseCase updateNotificationPreferences,
    required AuthCubit authCubit,
  })  : _searchProviders = searchProviders,
        _searchSlots = searchSlots,
        _holdSlot = holdSlot,
        _confirmBooking = confirmBooking,
        _register = register,
        _updateAccount = updateAccount,
        _updateNotificationPreferences = updateNotificationPreferences,
        _authCubit = authCubit,
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

    // #5362 : un visiteur anonyme n'a pas encore de session patient (le
    // hold requiert un JWT) — sélectionner un créneau reste une pure
    // interaction UI pour lui ; le hold n'est posé qu'à la confirmation,
    // juste après la création du compte, dans le même geste.
    if (_authCubit.state is! AuthAuthenticated) {
      safeEmit(current.copyWith(selectedSlot: event.slot));
      return;
    }

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
    if (slot == null || current.motif.trim().isEmpty) return;
    final precisions = event.precisions.trim();
    final motif = precisions.isEmpty
        ? current.motif.trim()
        : '${current.motif.trim()}\n\nPrécisions : $precisions';

    emit(const AppointmentsBookingLoading());
    try {
      // #5362 : « le compte se crée avec le rendez-vous, jamais avant » —
      // un visiteur anonyme n'a encore ni session ni hold à ce stade ; les
      // trois étapes (compte, hold, réservation) se jouent dans le même
      // geste de confirmation, sans écran intermédiaire.
      if (event.createAccount) {
        final registerResult = await _register(
          email: event.email.trim(),
          password: _generateGuestPassword(),
          acceptCgu: event.cguAccepted,
          cguVersion: _kGuestCguVersion,
        );
        final registerFailure =
            registerResult.fold((failure) => failure, (_) => null);
        if (registerFailure != null) {
          safeEmit(AppointmentsError(registerFailure.message));
          return;
        }
        await _authCubit.restore();
        await _updateAccount(
          firstName: event.firstName.trim(),
          lastName: event.lastName.trim(),
          phone: event.phone.trim(),
          dateOfBirth: event.dateOfBirth,
        );
        await _updateNotificationPreferences(
          const NotificationPreferences.allEnabled()
              .copyWith(appointments: event.remindersEnabled),
        );
      }

      var holdToken = current.holdToken;
      if (holdToken == null) {
        final holdResult = await _holdSlot(slot.id);
        final (holdFailure, newHoldToken) = holdResult.fold(
          (failure) => (failure, null),
          (hold) => (null, hold.token),
        );
        if (holdFailure != null) {
          safeEmit(AppointmentsError(holdFailure.message));
          return;
        }
        holdToken = newHoldToken;
      }

      final result = await _confirmBooking(
        slotId: slot.id,
        holdToken: holdToken!,
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
