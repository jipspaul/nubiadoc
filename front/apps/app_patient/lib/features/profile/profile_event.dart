import 'package:equatable/equatable.dart';

sealed class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object?> get props => [];
}

final class ProfileLoadRequested extends ProfileEvent {
  const ProfileLoadRequested();
}

final class BiometricToggleRequested extends ProfileEvent {
  const BiometricToggleRequested({required this.enabled});

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class ToggleEmailRdv extends ProfileEvent {
  const ToggleEmailRdv({required this.enabled});

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class TogglePushRdv extends ProfileEvent {
  const TogglePushRdv({required this.enabled});

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

/// #4544 : "Informations personnelles" affichait le téléphone dans un champ
/// désactivé sans aucun moyen de le modifier (l'email, lui, reste
/// volontairement non modifiable — back-end : `PATCH /v1/account` renvoie
/// 422 si `email` est présent).
final class PhoneUpdateRequested extends ProfileEvent {
  const PhoneUpdateRequested(this.phone);

  final String phone;

  @override
  List<Object?> get props => [phone];
}
