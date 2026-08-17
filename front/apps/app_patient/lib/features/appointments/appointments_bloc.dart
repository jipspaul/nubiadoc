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
      await result.fold(
        (failure) async => emit(AppointmentsError(failure.message)),
        (providers) async {
          // #5357 : la carte résultat affiche 3 jours de créneaux réels (pas
          // seulement le nom) — on les résout avant d'émettre pour que la
          // liste n'apparaisse jamais sans ses créneaux.
          final slotsByProvider = await _fetchSlotsByProvider(providers);
          _lastProvidersLoaded = AppointmentsProvidersLoaded(
            providers: providers,
            query: query,
            slotsByProvider: slotsByProvider,
          );
          emit(_lastProvidersLoaded);
        },
      );
    } catch (_) {
      emit(const AppointmentsError('Erreur de recherche.'));
    }
  }

  /// Résout les créneaux de chaque praticien pour l'aperçu de la carte
  /// résultat (#5357). Un échec isolé (praticien sans agenda, erreur réseau
  /// ponctuelle) n'affiche simplement aucun créneau pour lui — il ne doit
  /// jamais faire échouer la recherche entière.
  Future<Map<String, List<Slot>>> _fetchSlotsByProvider(
    List<ProviderResult> providers,
  ) async {
    final entries = await Future.wait(providers.map((provider) async {
      try {
        final result = await _searchSlots(providerId: provider.id);
        return MapEntry(
          provider.id,
          result.fold((_) => const <Slot>[], (slots) => slots),
        );
      } catch (_) {
        return MapEntry(provider.id, const <Slot>[]);
      }
    }));
    return Map.fromEntries(entries);
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
      await result.fold(
        (failure) async => safeEmit(AppointmentsError(failure.message)),
        (slots) async {
          final loaded =
              AppointmentsSlotsLoaded(provider: event.provider, slots: slots);
          safeEmit(loaded);
          // #5357 : venu d'un clic sur une puce créneau de la carte
          // résultat — on enchaîne directement sur la sélection de ce
          // créneau (démarre la réservation) une fois l'agenda chargé.
          final preselectId = event.preselectSlotId;
          if (preselectId == null) return;
          final preselect =
              slots.where((s) => s.id == preselectId && s.isAvailable);
          if (preselect.isEmpty) return;
          await _selectSlot(loaded, preselect.first, emit);
        },
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
    await _selectSlot(current, event.slot, emit);
  }

  Future<void> _selectSlot(
    AppointmentsSlotsLoaded current,
    Slot slot,
    Emitter<AppointmentsState> emit,
  ) async {
    // #5362 : un visiteur anonyme n'a pas encore de session patient (le
    // hold requiert un JWT) — sélectionner un créneau reste une pure
    // interaction UI pour lui ; le hold n'est posé qu'à la confirmation,
    // juste après la création du compte, dans le même geste.
    if (_authCubit.state is! AuthAuthenticated) {
      safeEmit(current.copyWith(selectedSlot: slot));
      return;
    }

    try {
      final holdResult = await _holdSlot(slot.id);
      holdResult.fold(
        (failure) => safeEmit(AppointmentsError(failure.message)),
        (hold) => safeEmit(current.copyWith(
          selectedSlot: slot,
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

    emit(AppointmentsBookingLoading(
      provider: current.provider,
      selectedSlot: slot,
      motif: current.motif,
    ));
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
