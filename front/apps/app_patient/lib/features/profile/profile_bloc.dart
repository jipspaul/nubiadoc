import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'profile_event.dart';
import 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> with SafeEmitMixin<ProfileState> {
  final GetAccountUseCase _getAccount;
  final UserSettingsRepository _userSettings;
  final NotificationRepository _notificationRepo;

  ProfileBloc({
    required GetAccountUseCase getAccount,
    required UserSettingsRepository userSettings,
    required NotificationRepository notificationRepo,
  })  : _getAccount = getAccount,
        _userSettings = userSettings,
        _notificationRepo = notificationRepo,
        super(const ProfileInitial()) {
    on<ProfileLoadRequested>(_onLoadRequested);
    on<BiometricToggleRequested>(_onBiometricToggle);
    on<ToggleEmailRdv>(_onToggleEmailRdv);
    on<TogglePushRdv>(_onTogglePushRdv);
  }

  Future<void> _onLoadRequested(
    ProfileLoadRequested event,
    Emitter<ProfileState> emit,
  ) async {
    emit(const ProfileLoading());
    try {
      final result = await _getAccount();
      await result.fold(
        (failure) async => safeEmit(ProfileError(failure.message)),
        (account) async {
          final biometric = await _userSettings.getBiometricEnabled();
          final prefsResult = await _notificationRepo.getPreferences();
          final prefs = prefsResult.fold((_) => null, (p) => p);
          safeEmit(ProfileLoaded(account,
              biometricEnabled: biometric, notifPrefs: prefs));
        },
      );
    } catch (_) {
      safeEmit(const ProfileError('Erreur de chargement du profil.'));
    }
  }

  Future<void> _onBiometricToggle(
    BiometricToggleRequested event,
    Emitter<ProfileState> emit,
  ) async {
    try {
      await _userSettings.setBiometricEnabled(event.enabled);
      if (state is ProfileLoaded) {
        final current = state as ProfileLoaded;
        safeEmit(ProfileLoaded(current.account,
            biometricEnabled: event.enabled, notifPrefs: current.notifPrefs));
      }
    } catch (_) {
      // Keep current state — no Loading was emitted
    }
  }

  Future<void> _onToggleEmailRdv(
    ToggleEmailRdv event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    final current = state as ProfileLoaded;
    final updated =
        (current.notifPrefs ?? const NotificationPreferences.allEnabled())
            .copyWith(emailEnabled: event.enabled);
    try {
      await _notificationRepo.updatePreferences(updated);
      safeEmit(ProfileLoaded(current.account,
          biometricEnabled: current.biometricEnabled, notifPrefs: updated));
    } catch (_) {
      // Keep current state — no Loading was emitted
    }
  }

  Future<void> _onTogglePushRdv(
    TogglePushRdv event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    final current = state as ProfileLoaded;
    final updated =
        (current.notifPrefs ?? const NotificationPreferences.allEnabled())
            .copyWith(pushEnabled: event.enabled);
    try {
      await _notificationRepo.updatePreferences(updated);
      safeEmit(ProfileLoaded(current.account,
          biometricEnabled: current.biometricEnabled, notifPrefs: updated));
    } catch (_) {
      // Keep current state — no Loading was emitted
    }
  }
}
