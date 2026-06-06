import 'package:equatable/equatable.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Déclenche la connexion avec email + mot de passe.
final class AuthLoginRequested extends AuthEvent {
  const AuthLoginRequested({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

/// Déclenche la création de compte patient.
final class AuthRegisterRequested extends AuthEvent {
  const AuthRegisterRequested({
    required this.email,
    required this.password,
    required this.cguVersion,
  });

  final String email;
  final String password;
  final String cguVersion;

  @override
  List<Object?> get props => [email, password, cguVersion];
}

/// Déclenche la déconnexion.
final class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

/// Vérifie si un token persisté existe au démarrage.
final class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}
