import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_team_messages_repository.dart';

class UnpinCabinetTeamMessageUseCase {
  final CabinetTeamMessagesRepository _repository;

  const UnpinCabinetTeamMessageUseCase(this._repository);

  Future<Either<Failure, void>> call(String messageId) =>
      _repository.unpin(messageId);
}
