import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_conversation.dart';
import 'package:nubia_domain/src/repositories/cabinet_message_repository.dart';

class ListCabinetConversationsUseCase {
  final CabinetMessageRepository _repository;

  const ListCabinetConversationsUseCase(this._repository);

  Future<Either<Failure, List<CabinetConversation>>> call() =>
      _repository.getConversations();
}
