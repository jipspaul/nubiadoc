import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_team_message.dart';
import 'package:nubia_domain/src/repositories/cabinet_team_messages_repository.dart';

class ListCabinetTeamMessagesUseCase {
  final CabinetTeamMessagesRepository _repository;

  const ListCabinetTeamMessagesUseCase(this._repository);

  Future<Either<Failure, List<CabinetTeamMessage>>> call() =>
      _repository.list();
}
