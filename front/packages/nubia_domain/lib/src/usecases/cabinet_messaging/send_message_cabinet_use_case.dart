import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/message.dart';
import 'package:nubia_domain/src/repositories/cabinet_message_repository.dart';

class SendMessageCabinetUseCase {
  final CabinetMessageRepository _repository;

  const SendMessageCabinetUseCase(this._repository);

  Future<Either<Failure, Message>> call({
    required String conversationId,
    required String text,
    List<String> attachmentIds = const [],
  }) =>
      _repository.send(
        conversationId: conversationId,
        text: text,
        attachmentIds: attachmentIds,
      );
}
