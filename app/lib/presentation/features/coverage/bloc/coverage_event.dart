import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/account_repository.dart';

sealed class CoverageEvent extends Equatable {
  const CoverageEvent();

  @override
  List<Object?> get props => [];
}

final class CoverageLoadRequested extends CoverageEvent {
  const CoverageLoadRequested();
}

final class CoverageCardUploadRequested extends CoverageEvent {
  final String filePath;
  final String mimeType;
  final CoverageCardSide side;

  const CoverageCardUploadRequested({
    required this.filePath,
    required this.mimeType,
    required this.side,
  });

  @override
  List<Object?> get props => [filePath, mimeType, side];
}

final class CoverageThirdPartyPaymentToggled extends CoverageEvent {
  final HealthInsuranceRegime regime;
  final String? amc;
  final String? numeroAdherent;
  final bool thirdPartyPayment;

  const CoverageThirdPartyPaymentToggled({
    required this.regime,
    this.amc,
    this.numeroAdherent,
    required this.thirdPartyPayment,
  });

  @override
  List<Object?> get props => [regime, amc, numeroAdherent, thirdPartyPayment];
}
