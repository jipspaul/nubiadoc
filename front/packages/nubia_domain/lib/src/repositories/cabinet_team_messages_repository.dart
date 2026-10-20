import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_team_message.dart';

abstract class CabinetTeamMessagesRepository {
  Future<Either<Failure, List<CabinetTeamMessage>>> list();

  /// Messages épinglés du fil, quel que soit leur âge (#8205) — distinct de
  /// [list], qui ne sert que les messages les plus récents.
  Future<Either<Failure, List<CabinetTeamMessage>>> listPinned();

  /// Retourne l'id du message envoyé. [reference] joint un objet réel du
  /// produit (patient, devis…) au message (#5131/#8228).
  Future<Either<Failure, String>> send(
    String body, {
    CabinetTeamMessageReference? reference,
  });

  /// Épingle un message existant du fil (#5130/#8181).
  Future<Either<Failure, void>> pin(String messageId);

  /// Désépingle un message existant du fil (#8204, pendant de [pin]).
  Future<Either<Failure, void>> unpin(String messageId);
}
