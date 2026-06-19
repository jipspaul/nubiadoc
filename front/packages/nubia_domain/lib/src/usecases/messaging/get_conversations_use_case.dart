import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/message.dart';
import 'package:nubia_domain/src/repositories/message_repository.dart';

class GetConversationsUseCase {
  final MessageRepository _repository;

  const GetConversationsUseCase(this._repository);

  Future<Either<Failure, List<Conversation>>> call() =>
      _repository.getConversations();
}
