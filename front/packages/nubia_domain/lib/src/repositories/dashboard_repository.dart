import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';

class DashboardSummary {
  final int upcomingAppointments;
  final int documentsToSign;
  final int pendingPaymentsCents;
  final int unreadMessages;
  final int pendingQuestionnaires;
  const DashboardSummary({
    required this.upcomingAppointments,
    required this.documentsToSign,
    required this.pendingPaymentsCents,
    required this.unreadMessages,
    required this.pendingQuestionnaires,
  });
}

abstract class DashboardRepository {
  /// Aggregated summary for the home screen badges.
  Future<Either<Failure, DashboardSummary>> getSummary();
}
