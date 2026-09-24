import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_conversation.dart';
import 'package:nubia_domain/src/entities/conversation_appointment_conversion.dart';
import 'package:nubia_domain/src/entities/message.dart';

abstract class CabinetMessageRepository {
  Future<Either<Failure, List<CabinetConversation>>> getConversations();
  Future<Either<Failure, List<Message>>> getMessages(String conversationId);
  Future<Either<Failure, Message>> send({
    required String conversationId,
    required String text,
    List<String> attachmentIds = const [],
  });

  /// POST /v1/cabinet/conversations/{id}/convert-to-appointment (#4159/#4160).
  Future<Either<Failure, ConversationAppointmentConversion>>
      convertToAppointment({
    required String conversationId,
    required String slotId,
  });

  /// PATCH /v1/cabinet/conversations/{id} — assigne la conversation à un
  /// membre du cabinet (#7151/#7150). Pas de moyen de désassigner par ce
  /// biais : même limite documentée côté API.
  Future<Either<Failure, void>> assignConversation({
    required String conversationId,
    required String assigneeUserId,
  });
}
