import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/message_repository.dart';

class MarkConversationReadUseCase {
  final MessageRepository _repository;

  const MarkConversationReadUseCase(this._repository);

  Future<Either<Failure, void>> call(String conversationId) =>
      _repository.markRead(conversationId);
}
