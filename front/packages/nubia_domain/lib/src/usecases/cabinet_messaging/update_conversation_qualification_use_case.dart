import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_message_repository.dart';

/// Qualifie une conversation cabinet — origine, priorité, statut, synthèse
/// (#7609). `motif` volontairement absent, cf.
/// `CabinetMessageRepository.updateQualification`.
class UpdateConversationQualificationUseCase {
  final CabinetMessageRepository _repository;

  const UpdateConversationQualificationUseCase(this._repository);

  Future<Either<Failure, void>> call({
    required String conversationId,
    String? origin,
    String? priority,
    String? status,
    String? summary,
  }) =>
      _repository.updateQualification(
        conversationId: conversationId,
        origin: origin,
        priority: priority,
        status: status,
        summary: summary,
      );
}
