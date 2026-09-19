import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/rendered_consent_template.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/consent_template_repository.dart';

class RenderConsentTemplateUseCase {
  final ConsentTemplateRepository _repository;

  const RenderConsentTemplateUseCase(this._repository);

  Future<Either<Failure, RenderedConsentTemplate>> call(
    String id, {
    required String quoteId,
  }) =>
      _repository.render(id, quoteId: quoteId);
}
