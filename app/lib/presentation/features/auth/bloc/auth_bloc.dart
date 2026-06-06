import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/repositories/auth_repository.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_event.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_state.dart';

@injectable
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  AuthBloc(this._authRepository) : super(const AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthRefreshRequested>(_onRefreshRequested);
  }

  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    final authenticated = await _authRepository.isAuthenticated();
    if (!authenticated) {
      emit(const AuthUnauthenticated());
      return;
    }
    final result = await _authRepository.getMe();
    result.fold(
      (_) => emit(const AuthUnauthenticated()),
      (account) => emit(AuthAuthenticated(account)),
    );
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final result = await _authRepository.login(
      email: event.email,
      password: event.password,
    );
    result.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (account) => emit(AuthAuthenticated(account)),
    );
  }

  Future<void> _onRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final result = await _authRepository.register(
      email: event.email,
      password: event.password,
      inviteToken: event.inviteToken,
    );
    result.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (account) => emit(AuthAuthenticated(account)),
    );
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authRepository.logout();
    emit(const AuthUnauthenticated());
  }

  Future<void> _onRefreshRequested(
    AuthRefreshRequested event,
    Emitter<AuthState> emit,
  ) async {
    final result = await _authRepository.refreshToken();
    result.fold(
      (_) => emit(const AuthUnauthenticated()),
      (_) => null,
    );
  }
}
