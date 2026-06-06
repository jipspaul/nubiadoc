import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';

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

  const ProfileLoaded(this.account);

  @override
  List<Object?> get props => [account];
}

final class ProfileError extends ProfileState {
  final String message;

  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}
