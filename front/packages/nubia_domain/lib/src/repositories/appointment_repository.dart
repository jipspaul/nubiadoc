import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/appointment.dart';
import 'package:nubia_domain/src/entities/appointment_preparation.dart';
import 'package:nubia_domain/src/entities/directions_result.dart';

/// Une page unique d'historique de rendez-vous (#8365) : [nextCursor] permet
/// de charger la suivante à la demande plutôt que de suivre les curseurs
/// jusqu'à épuisement avant le premier rendu — même doctrine que
/// `PagedDocuments` (#8279/#8297) et `PagedNotifications` (#8323).
typedef PagedAppointments = ({
  List<Appointment> appointments,
  String? nextCursor,
});

abstract class AppointmentRepository {
  Future<Either<Failure, List<Appointment>>> getUpcoming();

  /// Charge une page unique d'historique (#8365) : [cursor] (issu d'un appel
  /// précédent) enchaîne sur `page.next_cursor` au lieu de paginer jusqu'à
  /// épuisement avant de rendre la main — l'onglet Historique suivait
  /// jusque-là ce chemin (13 requêtes séquentielles / 4 s de squelettes
  /// avant le premier rendu, cf. #8365).
  Future<Either<Failure, PagedAppointments>> getHistoryPage({
    int limit = 20,
    String? cursor,
  });
  Future<Either<Failure, Appointment>> getById(String id);
  Future<Either<Failure, Appointment>> book({
    required String slotId,
    required String motif,
  });
  Future<Either<Failure, Appointment>> cancel(String id);
  Future<Either<Failure, Appointment>> modify({
    required String id,
    required DateTime newStartsAt,
  });
  Future<Either<Failure, Appointment>> checkin(String id);
  Future<Either<Failure, DirectionsResult>> getDirections(
    String id, {
    String mode = 'car',
  });
  Future<Either<Failure, AppointmentPreparation>> getPreparation(String id);
}
