import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';

sealed class AccountEvent extends Equatable {
  const AccountEvent();

  @override
  List<Object?> get props => [];
}

final class AccountLoadRequested extends AccountEvent {
  const AccountLoadRequested();
}

final class AccountUpdateRequested extends AccountEvent {
  final String? firstName;
  final String? lastName;
  final String? phone;

  const AccountUpdateRequested({this.firstName, this.lastName, this.phone});

  @override
  List<Object?> get props => [firstName, lastName, phone];
}

final class AccountCoverageLoadRequested extends AccountEvent {
  const AccountCoverageLoadRequested();
}

final class AccountCoverageUpdateRequested extends AccountEvent {
  final HealthInsuranceRegime regime;
  final String? amc;
  final String? numeroAdherent;
  final bool thirdPartyPayment;

  const AccountCoverageUpdateRequested({
    required this.regime,
    this.amc,
    this.numeroAdherent,
    this.thirdPartyPayment = false,
  });

  @override
  List<Object?> get props => [regime, amc, numeroAdherent, thirdPartyPayment];
}

final class AccountDependentsLoadRequested extends AccountEvent {
  const AccountDependentsLoadRequested();
}

final class AccountDependentAddRequested extends AccountEvent {
  final String firstName;
  final String lastName;
  final DateTime? birthDate;
  final DependentRelationship relationship;

  const AccountDependentAddRequested({
    required this.firstName,
    required this.lastName,
    this.birthDate,
    required this.relationship,
  });

  @override
  List<Object?> get props => [firstName, lastName, birthDate, relationship];
}

final class AccountDependentDeleteRequested extends AccountEvent {
  final String id;

  const AccountDependentDeleteRequested(this.id);

  @override
  List<Object?> get props => [id];
}
