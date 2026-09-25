import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/leave_request.dart';

abstract class LeaveRequestsRepository {
  /// GET /v1/cabinet/staff/leave-requests (#7143/#7144), filtrable par
  /// utilisateur/statut — le rôle `practitioner` est forcé à ses propres
  /// demandes côté back, quel que soit `userId`.
  Future<Either<Failure, List<LeaveRequest>>> list({
    String? userId,
    String? status,
  });

  /// POST /v1/cabinet/staff/leave-requests (#7143/#7144) — toujours pour
  /// soi-même (`user_id` = l'utilisateur courant côté back, jamais transmis
  /// par le client).
  Future<Either<Failure, LeaveRequest>> create({
    required String startsAt,
    required String endsAt,
    required String kind,
  });

  /// POST /v1/cabinet/staff/leave-requests/:id/decide (#7143/#7144) —
  /// validation manager, réservée admin/manager côté back (403 sinon).
  Future<Either<Failure, LeaveRequest>> decide({
    required String id,
    required bool approve,
  });

  /// POST /v1/cabinet/staff/leave-requests/:id/cancel (#7143/#7144) — le
  /// demandeur annule sa propre demande (`pending`/`approved` uniquement).
  Future<Either<Failure, LeaveRequest>> cancel(String id);
}
