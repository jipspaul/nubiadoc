import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// Détails du prochain RDV confirmé du patient, pour la carte héros de
/// l'accueil (design-v2). `practitionerName`/`reason`/`addressLines` sont
/// nullable tant que le backend ne les expose pas encore dans
/// `next_appointment` (#5197).
class NextAppointmentSummary {
  final String appointmentId;
  final DateTime startsAt;
  final String? practitionerName;
  final String? reason;
  final List<String>? addressLines;

  const NextAppointmentSummary({
    required this.appointmentId,
    required this.startsAt,
    this.practitionerName,
    this.reason,
    this.addressLines,
  });
}

class DashboardSummary {
  final int upcomingAppointments;
  final int documentsToSign;
  final int pendingPaymentsCents;
  final int unreadMessages;
  final NextAppointmentSummary? nextAppointment;
  const DashboardSummary({
    required this.upcomingAppointments,
    required this.documentsToSign,
    required this.pendingPaymentsCents,
    required this.unreadMessages,
    this.nextAppointment,
  });
}

abstract class DashboardRepository {
  /// Aggregated summary for the home screen badges.
  Future<Either<Failure, DashboardSummary>> getSummary();
}
