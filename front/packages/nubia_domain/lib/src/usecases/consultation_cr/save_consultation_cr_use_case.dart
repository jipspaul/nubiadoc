import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/consultation_cr.dart';
import 'package:nubia_domain/src/repositories/consultation_cr_repository.dart';

class SaveConsultationCrUseCase {
  final ConsultationCrRepository _repository;

  const SaveConsultationCrUseCase(this._repository);

  Future<Either<Failure, ConsultationCr>> call({
    required String consultationId,
    String? templateId,
    required List<CrSectionEntry> sections,
  }) =>
      _repository.saveConsultationCr(
        consultationId: consultationId,
        templateId: templateId,
        sections: sections,
      );
}
