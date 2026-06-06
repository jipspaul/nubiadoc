import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/repositories/message_repository.dart';

@injectable
class MarkConversationReadUseCase {
  final MessageRepository _repository;

  const MarkConversationReadUseCase(this._repository);

  Future<Either<Failure, void>> call(String conversationId) =>
      _repository.markRead(conversationId);
}
