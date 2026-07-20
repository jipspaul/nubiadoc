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

/// Couverture existante chargée — préremplit le formulaire (#3842).
final class CoverageSetupLoaded extends CoverageSetupState {
  final HealthCoverage coverage;
  const CoverageSetupLoaded(this.coverage);

  @override
  List<Object?> get props => [coverage];
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
  CoverageSetupCubit({
    required GetCoverageUseCase getCoverage,
    required UpdateCoverageUseCase updateCoverage,
  })  : _getCoverage = getCoverage,
        _updateCoverage = updateCoverage,
        super(const CoverageSetupIdle());

  final GetCoverageUseCase _getCoverage;
  final UpdateCoverageUseCase _updateCoverage;

  /// Charge la couverture existante (#3842) — cet écran est réutilisé pour
  /// l'onboarding (aucune couverture, formulaire vierge légitime) ET pour
  /// l'édition depuis le Profil (couverture réelle à précharger, sinon un
  /// « Enregistrer » écrase silencieusement la vraie couverture par les
  /// valeurs vides par défaut). Échec de lecture → formulaire vierge
  /// (dégradation gracieuse, pas de blocage de l'onboarding).
  Future<void> load() async {
    emit(const CoverageSetupLoading());
    final result = await _getCoverage();
    result.fold(
      (_) => safeEmit(const CoverageSetupIdle()),
      (coverage) => safeEmit(CoverageSetupLoaded(coverage)),
    );
  }

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

  void skipStep() => safeEmit(const CoverageSetupSuccess());
}
