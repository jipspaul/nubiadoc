import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';

sealed class CoverageState extends Equatable {
  const CoverageState();

  @override
  List<Object?> get props => [];
}

final class CoverageInitial extends CoverageState {
  const CoverageInitial();
}

final class CoverageLoading extends CoverageState {
  const CoverageLoading();
}

final class CoverageLoaded extends CoverageState {
  final HealthCoverage coverage;

  const CoverageLoaded(this.coverage);

  @override
  List<Object?> get props => [coverage];
}

final class CoverageError extends CoverageState {
  final String message;

  const CoverageError(this.message);

  @override
  List<Object?> get props => [message];
}

// ─── Card upload ─────────────────────────────────────────────────────────────

final class CoverageCardUploading extends CoverageState {
  final HealthCoverage coverage;

  const CoverageCardUploading(this.coverage);

  @override
  List<Object?> get props => [coverage];
}

final class CoverageCardUploaded extends CoverageState {
  final HealthCoverage coverage;
  final String documentId;

  const CoverageCardUploaded({required this.coverage, required this.documentId});

  @override
  List<Object?> get props => [coverage, documentId];
}

final class CoverageCardUploadError extends CoverageState {
  final HealthCoverage coverage;
  final String message;

  const CoverageCardUploadError({required this.coverage, required this.message});

  @override
  List<Object?> get props => [coverage, message];
}
