import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';

class ProDashboardSummary {
  final int todayAppointments;
  final int waitingRoomCount;
  final int unreadMessages;
  final int pendingConfirmations;

  const ProDashboardSummary({
    required this.todayAppointments,
    required this.waitingRoomCount,
    required this.unreadMessages,
    required this.pendingConfirmations,
  });
}

abstract class CabinetDashboardRepository {
  Future<Either<Failure, ProDashboardSummary>> getSummary();
}
