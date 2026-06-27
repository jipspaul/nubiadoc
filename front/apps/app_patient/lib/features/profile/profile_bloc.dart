import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'profile_event.dart';
import 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState>
    with SafeEmitMixin<ProfileState> {
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
    if (state is! ProfileLoaded) return;
    final previous = state as ProfileLoaded;
    emit(ProfileLoaded(previous.account,
        biometricEnabled: event.enabled, notifPrefs: previous.notifPrefs));
    try {
      await _userSettings.setBiometricEnabled(event.enabled);
    } catch (e) {
      emit(ProfileToggleFailed(previous, e.toString()));
    }
  }

  Future<void> _onToggleEmailRdv(
    ToggleEmailRdv event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    final previous = state as ProfileLoaded;
    final updated =
        (previous.notifPrefs ?? const NotificationPreferences.allEnabled())
            .copyWith(emailEnabled: event.enabled);
    emit(ProfileLoaded(previous.account,
        biometricEnabled: previous.biometricEnabled, notifPrefs: updated));
    try {
      await _notificationRepo.updatePreferences(updated);
    } catch (e) {
      emit(ProfileToggleFailed(previous, e.toString()));
    }
  }

  Future<void> _onTogglePushRdv(
    TogglePushRdv event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    final previous = state as ProfileLoaded;
    final updated =
        (previous.notifPrefs ?? const NotificationPreferences.allEnabled())
            .copyWith(pushEnabled: event.enabled);
    emit(ProfileLoaded(previous.account,
        biometricEnabled: previous.biometricEnabled, notifPrefs: updated));
    try {
      await _notificationRepo.updatePreferences(updated);
    } catch (e) {
      emit(ProfileToggleFailed(previous, e.toString()));
    }
  }
}
