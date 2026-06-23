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
