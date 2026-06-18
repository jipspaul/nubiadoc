import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/message.dart';
import 'package:nubia_domain/src/repositories/message_repository.dart';

class GetConversationMessagesUseCase {
  final MessageRepository _repository;

  const GetConversationMessagesUseCase(this._repository);

  Future<Either<Failure, List<Message>>> call(String conversationId) =>
      _repository.getMessages(conversationId);
}
