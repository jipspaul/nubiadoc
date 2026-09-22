import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/equipment.dart';
import 'package:nubia_domain/src/entities/maintenance_stats.dart';
import 'package:nubia_domain/src/entities/maintenance_ticket.dart';

abstract class MaintenanceRepository {
  /// GET /v1/cabinet/maintenance/stats (#7167).
  Future<Either<Failure, MaintenanceStats>> getStats();

  /// GET /v1/cabinet/equipment (#7167), trié par libellé.
  Future<Either<Failure, List<Equipment>>> listEquipment();

  /// GET /v1/cabinet/maintenance/tickets (#7167), filtrable par
  /// statut/équipement.
  Future<Either<Failure, List<MaintenanceTicket>>> listTickets({
    String? status,
    String? equipmentId,
  });

  /// POST /v1/cabinet/maintenance/photos (#7167) — uploade une photo au
  /// coffre-fort cabinet, renvoie le `document_id` à référencer via
  /// [createTicket]'s `photoDocumentIds`.
  Future<Either<Failure, String>> uploadPhoto({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  });

  /// POST /v1/cabinet/maintenance/tickets (#7167) — crée un ticket (statut
  /// `open`), e-mail au technicien géré côté back.
  Future<Either<Failure, MaintenanceTicket>> createTicket({
    String? equipmentId,
    required String title,
    String? description,
    String? priority,
    String? assignedToEmail,
    List<String> photoDocumentIds = const [],
  });
}
