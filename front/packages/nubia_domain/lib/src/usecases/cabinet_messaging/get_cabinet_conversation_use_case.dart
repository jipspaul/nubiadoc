import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/message.dart';
import 'package:nubia_domain/src/repositories/cabinet_message_repository.dart';

class GetCabinetConversationUseCase {
  final CabinetMessageRepository _repository;

  const GetCabinetConversationUseCase(this._repository);

  Future<Either<Failure, List<Message>>> call(String conversationId) =>
      _repository.getMessages(conversationId);
}
