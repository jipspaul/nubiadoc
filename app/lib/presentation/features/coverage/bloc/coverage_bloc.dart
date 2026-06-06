import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/usecases/account/get_coverage_use_case.dart';
import 'package:nubia_patient/domain/usecases/account/upload_coverage_card_use_case.dart';
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_event.dart';
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_state.dart';

@injectable
class CoverageBloc extends Bloc<CoverageEvent, CoverageState> {
  final GetCoverageUseCase _getCoverage;
  final UploadCoverageCardUseCase _uploadCard;

  CoverageBloc(this._getCoverage, this._uploadCard)
      : super(const CoverageInitial()) {
    on<CoverageLoadRequested>(_onLoadRequested);
    on<CoverageCardUploadRequested>(_onCardUploadRequested);
    on<CoverageThirdPartyPaymentToggled>(_onThirdPartyPaymentToggled);
  }

  Future<void> _onLoadRequested(
    CoverageLoadRequested event,
    Emitter<CoverageState> emit,
  ) async {
    emit(const CoverageLoading());
    final result = await _getCoverage();
    result.fold(
      (failure) => emit(CoverageError(failure.message)),
      (coverage) => emit(CoverageLoaded(coverage)),
    );
  }

  Future<void> _onCardUploadRequested(
    CoverageCardUploadRequested event,
    Emitter<CoverageState> emit,
  ) async {
    final current = state;
    final coverage = _currentCoverage(current);
    if (coverage == null) return;

    emit(CoverageCardUploading(coverage));
    final result = await _uploadCard(
      filePath: event.filePath,
      mimeType: event.mimeType,
      side: event.side,
    );
    result.fold(
      (failure) => emit(CoverageCardUploadError(
        coverage: coverage,
        message: failure.message,
      )),
      (documentId) => emit(CoverageCardUploaded(
        coverage: coverage,
        documentId: documentId,
      )),
    );
  }

  Future<void> _onThirdPartyPaymentToggled(
    CoverageThirdPartyPaymentToggled event,
    Emitter<CoverageState> emit,
  ) async {
    final current = state;
    final coverage = _currentCoverage(current);
    if (coverage == null) return;

    emit(const CoverageLoading());
    // Re-use AccountRepository via GetCoverageUseCase after update would
    // require UpdateCoverageUseCase — delegate to AccountBloc for now.
    // This event carries the full updated coverage for the UI to optimistically
    // reflect the toggle while the caller uses AccountBloc for the PATCH.
    final updated = _buildUpdatedCoverage(coverage, event);
    emit(CoverageLoaded(updated));
  }

  HealthCoverage? _currentCoverage(CoverageState s) {
    if (s is CoverageLoaded) return s.coverage;
    if (s is CoverageCardUploading) return s.coverage;
    if (s is CoverageCardUploaded) return s.coverage;
    if (s is CoverageCardUploadError) return s.coverage;
    return null;
  }

  static HealthCoverage _buildUpdatedCoverage(
    HealthCoverage current,
    CoverageThirdPartyPaymentToggled event,
  ) {
    return HealthCoverage(
      regime: event.regime,
      insuranceName: event.amc,
      memberNumber: event.numeroAdherent,
      thirdPartyPayment: event.thirdPartyPayment,
      nssPartial: current.nssPartial,
    );
  }
}
