import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ProfileState extends Equatable {
  const ProfileState();

  @override
  List<Object?> get props => [];
}

final class ProfileInitial extends ProfileState {
  const ProfileInitial();
}

final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

final class ProfileLoaded extends ProfileState {
  final PatientAccount account;
  final bool biometricEnabled;
  final NotificationPreferences? notifPrefs;
  final bool phoneUpdating;

  const ProfileLoaded(
    this.account, {
    this.biometricEnabled = false,
    this.notifPrefs,
    this.phoneUpdating = false,
  });

  @override
  List<Object?> get props =>
      [account, biometricEnabled, notifPrefs, phoneUpdating];
}

final class ProfileError extends ProfileState {
  final String message;

  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}

final class ProfileToggleFailed extends ProfileState {
  final ProfileLoaded previousState;
  final String message;

  const ProfileToggleFailed(this.previousState, this.message);

  @override
  List<Object?> get props => [previousState, message];
}
