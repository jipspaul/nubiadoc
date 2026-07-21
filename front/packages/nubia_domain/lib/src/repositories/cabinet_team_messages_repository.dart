import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_team_message.dart';

abstract class CabinetTeamMessagesRepository {
  Future<Either<Failure, List<CabinetTeamMessage>>> list();

  /// Retourne l'id du message envoyé.
  Future<Either<Failure, String>> send(String body);
}
