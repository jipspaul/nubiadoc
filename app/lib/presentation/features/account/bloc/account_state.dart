import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';

sealed class AccountState extends Equatable {
  const AccountState();

  @override
  List<Object?> get props => [];
}

final class AccountInitial extends AccountState {
  const AccountInitial();
}

final class AccountLoading extends AccountState {
  const AccountLoading();
}

final class AccountLoaded extends AccountState {
  final PatientAccount account;

  const AccountLoaded(this.account);

  @override
  List<Object?> get props => [account];
}

final class AccountError extends AccountState {
  final String message;

  const AccountError(this.message);

  @override
  List<Object?> get props => [message];
}

// ─── Coverage ────────────────────────────────────────────────────────────────

final class AccountCoverageLoading extends AccountState {
  const AccountCoverageLoading();
}

final class AccountCoverageLoaded extends AccountState {
  final HealthCoverage coverage;

  const AccountCoverageLoaded(this.coverage);

  @override
  List<Object?> get props => [coverage];
}

final class AccountCoverageUpdating extends AccountState {
  final HealthCoverage current;

  const AccountCoverageUpdating(this.current);

  @override
  List<Object?> get props => [current];
}

final class AccountCoverageUpdated extends AccountState {
  final HealthCoverage coverage;

  const AccountCoverageUpdated(this.coverage);

  @override
  List<Object?> get props => [coverage];
}

final class AccountCoverageError extends AccountState {
  final String message;

  const AccountCoverageError(this.message);

  @override
  List<Object?> get props => [message];
}

// ─── Dependents ──────────────────────────────────────────────────────────────

final class AccountDependentsLoading extends AccountState {
  const AccountDependentsLoading();
}

final class AccountDependentsLoaded extends AccountState {
  final List<Dependent> dependents;

  const AccountDependentsLoaded(this.dependents);

  @override
  List<Object?> get props => [dependents];
}

final class AccountDependentAdded extends AccountState {
  final List<Dependent> dependents;

  const AccountDependentAdded(this.dependents);

  @override
  List<Object?> get props => [dependents];
}

final class AccountDependentsError extends AccountState {
  final String message;

  const AccountDependentsError(this.message);

  @override
  List<Object?> get props => [message];
}

// ─── Profile update ──────────────────────────────────────────────────────────

final class AccountUpdating extends AccountState {
  const AccountUpdating();
}

final class AccountUpdated extends AccountState {
  final PatientAccount account;

  const AccountUpdated(this.account);

  @override
  List<Object?> get props => [account];
}
