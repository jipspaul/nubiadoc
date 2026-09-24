import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/consultation_cr.dart';
import 'package:nubia_domain/src/repositories/consultation_cr_repository.dart';

class FinalizeConsultationCrUseCase {
  final ConsultationCrRepository _repository;

  const FinalizeConsultationCrUseCase(this._repository);

  Future<Either<Failure, ConsultationCr>> call(String consultationId) =>
      _repository.finalizeConsultationCr(consultationId);
}
