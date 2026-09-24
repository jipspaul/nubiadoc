import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_message_repository.dart';

class AssignCabinetConversationUseCase {
  final CabinetMessageRepository _repository;

  const AssignCabinetConversationUseCase(this._repository);

  Future<Either<Failure, void>> call({
    required String conversationId,
    required String assigneeUserId,
  }) =>
      _repository.assignConversation(
        conversationId: conversationId,
        assigneeUserId: assigneeUserId,
      );
}
