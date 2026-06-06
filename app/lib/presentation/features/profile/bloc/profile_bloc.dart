import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/repositories/auth_repository.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_event.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_state.dart';

@injectable
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final AuthRepository _authRepository;

  ProfileBloc(this._authRepository) : super(const ProfileInitial()) {
    on<ProfileLoadRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
    ProfileLoadRequested event,
    Emitter<ProfileState> emit,
  ) async {
    emit(const ProfileLoading());
    final result = await _authRepository.getMe();
    result.fold(
      (failure) => emit(ProfileError(failure.message)),
      (account) => emit(ProfileLoaded(account)),
    );
  }
}
