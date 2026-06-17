import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'profile_event.dart';
import 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final GetAccountUseCase _getAccount;

  ProfileBloc({required GetAccountUseCase getAccount})
      : _getAccount = getAccount,
        super(const ProfileInitial()) {
    on<ProfileLoadRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
    ProfileLoadRequested event,
    Emitter<ProfileState> emit,
  ) async {
    emit(const ProfileLoading());
    final result = await _getAccount();
    result.fold(
      (failure) => emit(ProfileError(failure.message)),
      (account) => emit(ProfileLoaded(account)),
    );
  }
}
