import 'package:equatable/equatable.dart';

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// État initial — vérification du token en cours.
final class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Opération en cours (login / register / logout).
final class AuthLoading extends AuthState {
  const AuthLoading();
}

/// Authentifié — token disponible.
final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.accessToken});

  final String accessToken;

  @override
  List<Object?> get props => [accessToken];
}

/// Non authentifié.
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// Erreur lors d'une opération auth.
final class AuthFailure extends AuthState {
  const AuthFailure({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}
