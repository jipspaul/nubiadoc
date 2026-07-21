import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/conversation_appointment_conversion.dart';
import 'package:nubia_domain/src/repositories/cabinet_message_repository.dart';

class ConvertConversationToAppointmentUseCase {
  final CabinetMessageRepository _repository;

  const ConvertConversationToAppointmentUseCase(this._repository);

  Future<Either<Failure, ConversationAppointmentConversion>> call({
    required String conversationId,
    required String slotId,
  }) =>
      _repository.convertToAppointment(
        conversationId: conversationId,
        slotId: slotId,
      );
}
