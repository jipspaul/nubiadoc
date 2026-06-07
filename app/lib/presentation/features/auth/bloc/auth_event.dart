import 'package:equatable/equatable.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

final class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthLoginRequested({required this.email, required this.password});

  @override
  List<Object?> get props => [email, password];
}

final class AuthRegisterRequested extends AuthEvent {
  final String email;
  final String password;
  final String inviteToken;

  const AuthRegisterRequested({
    required this.email,
    required this.password,
    required this.inviteToken,
  });

  @override
  List<Object?> get props => [email, password, inviteToken];
}

final class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

final class AuthRefreshRequested extends AuthEvent {
  const AuthRefreshRequested();
}

final class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

/// Fired on app startup when a stored token may still be valid.
/// Alias for [AuthCheckRequested] with explicit naming for the splash flow.
final class SessionRestored extends AuthEvent {
  const SessionRestored();
}
