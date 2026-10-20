import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/cabinet_team_message.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_team_messages_repository.dart';

class SendCabinetTeamMessageUseCase {
  final CabinetTeamMessagesRepository _repository;

  const SendCabinetTeamMessageUseCase(this._repository);

  Future<Either<Failure, String>> call(
    String body, {
    CabinetTeamMessageReference? reference,
  }) =>
      _repository.send(body, reference: reference);
}
