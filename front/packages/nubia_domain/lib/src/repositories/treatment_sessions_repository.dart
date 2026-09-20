import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/treatment_session.dart';

abstract class TreatmentSessionsRepository {
  /// Répartit les actes du plan pas encore affectés à une séance, selon les
  /// règles du cabinet (`cabinet_session_rules`, résolues côté API).
  /// [defaultDurationMin] est la seule règle réglable depuis le front pour
  /// l'instant (durée par défaut d'un acte sans durée connue) — les autres
  /// règles (durée max, séparation d'arcade, regroupement par secteur, endo
  /// multiples) n'ont pas encore d'écran de réglage cabinet dédié.
  Future<Either<Failure, List<TreatmentSession>>> proposeSessions(
    String planId, {
    int? defaultDurationMin,
  });

  Future<Either<Failure, List<ProposedSlot>>> proposeSlots(
    String planId,
    String sessionId,
  );

  /// Réserve [slotId] pour la séance et crée le RDV lié. Retourne l'id du
  /// RDV créé.
  Future<Either<Failure, String>> scheduleSession(
    String planId,
    String sessionId,
    String slotId,
  );
}
