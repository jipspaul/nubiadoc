import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'profile_event.dart';
import 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final GetAccountUseCase _getAccount;
  final UserSettingsRepository _userSettings;

  ProfileBloc({
    required GetAccountUseCase getAccount,
    required UserSettingsRepository userSettings,
  })  : _getAccount = getAccount,
        _userSettings = userSettings,
        super(const ProfileInitial()) {
    on<ProfileLoadRequested>(_onLoadRequested);
    on<BiometricToggleRequested>(_onBiometricToggle);
  }

  Future<void> _onLoadRequested(
    ProfileLoadRequested event,
    Emitter<ProfileState> emit,
  ) async {
    emit(const ProfileLoading());
    final result = await _getAccount();
    await result.fold(
      (failure) async => emit(ProfileError(failure.message)),
      (account) async {
        final enabled = await _userSettings.getBiometricEnabled();
        emit(ProfileLoaded(account, biometricEnabled: enabled));
      },
    );
  }

  Future<void> _onBiometricToggle(
    BiometricToggleRequested event,
    Emitter<ProfileState> emit,
  ) async {
    await _userSettings.setBiometricEnabled(event.enabled);
    if (state is ProfileLoaded) {
      final current = state as ProfileLoaded;
      emit(ProfileLoaded(current.account, biometricEnabled: event.enabled));
    }
  }
}
