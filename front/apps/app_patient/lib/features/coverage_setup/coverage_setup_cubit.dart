import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class CoverageSetupState extends Equatable {
  const CoverageSetupState();

  @override
  List<Object?> get props => [];
}

final class CoverageSetupIdle extends CoverageSetupState {
  const CoverageSetupIdle();
}

final class CoverageSetupLoading extends CoverageSetupState {
  const CoverageSetupLoading();
}

final class CoverageSetupSuccess extends CoverageSetupState {
  const CoverageSetupSuccess();
}

final class CoverageSetupFailure extends CoverageSetupState {
  final String message;
  const CoverageSetupFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class CoverageSetupCubit extends Cubit<CoverageSetupState>
    with SafeEmitMixin<CoverageSetupState> {
  CoverageSetupCubit({required UpdateCoverageUseCase updateCoverage})
      : _updateCoverage = updateCoverage,
        super(const CoverageSetupIdle());

  final UpdateCoverageUseCase _updateCoverage;

  /// Soumet la couverture santé via PATCH /v1/account/coverage.
  Future<void> submit({
    required HealthInsuranceRegime regime,
    String? amc,
    String? numeroAdherent,
  }) async {
    emit(const CoverageSetupLoading());
    final result = await _updateCoverage(
      regime: regime,
      amc: amc,
      numeroAdherent: numeroAdherent,
    );
    result.fold(
      (failure) => safeEmit(CoverageSetupFailure(failure.message)),
      (_) => safeEmit(const CoverageSetupSuccess()),
    );
  }

  /// Passe l'étape sans enregistrer de données.
  void skip() => safeEmit(const CoverageSetupSuccess());
}
