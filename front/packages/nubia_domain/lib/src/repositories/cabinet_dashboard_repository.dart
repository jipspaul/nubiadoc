import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';

class ProDashboardSummary {
  final int todayAppointments;
  final int waitingRoomCount;
  final int unreadMessages;
  final int pendingConfirmations;

  /// Nombre d'actes réalisés cette semaine (lundi au vendredi, #5051).
  final int weeklyCompletedActs;

  /// Honoraires (encaissés + engagés) cette semaine, en centimes (#5051).
  final int weeklyFeesCents;

  /// Nombre de rendez-vous non honorés cette semaine (#5051).
  final int weeklyNoShowCount;

  const ProDashboardSummary({
    required this.todayAppointments,
    required this.waitingRoomCount,
    required this.unreadMessages,
    required this.pendingConfirmations,
    required this.weeklyCompletedActs,
    required this.weeklyFeesCents,
    required this.weeklyNoShowCount,
  });
}

abstract class CabinetDashboardRepository {
  Future<Either<Failure, ProDashboardSummary>> getSummary();
}
