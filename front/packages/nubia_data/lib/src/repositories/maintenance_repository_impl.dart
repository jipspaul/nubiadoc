import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/maintenance/maintenance_api.dart';
import 'package:nubia_domain/src/entities/equipment.dart';
import 'package:nubia_domain/src/entities/maintenance_stats.dart';
import 'package:nubia_domain/src/entities/maintenance_ticket.dart';
import 'package:nubia_domain/src/repositories/maintenance_repository.dart';

class MaintenanceRepositoryImpl implements MaintenanceRepository {
  final MaintenanceApi _api;

  const MaintenanceRepositoryImpl(this._api);

  @override
  Future<Either<Failure, MaintenanceStats>> getStats() async {
    try {
      final dto = await _api.getStats();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les compteurs de maintenance.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<Equipment>>> listEquipment() async {
    try {
      final dtos = await _api.listEquipment();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger l'inventaire des équipements.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<MaintenanceTicket>>> listTickets({
    String? status,
    String? equipmentId,
  }) async {
    try {
      final dtos =
          await _api.listTickets(status: status, equipmentId: equipmentId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les tickets de maintenance.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> uploadPhoto({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    try {
      final documentId = await _api.uploadPhoto(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
      return Right(documentId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 422) {
        return const Left(
            ValidationFailure(message: 'Photo invalide (format ou taille).'));
      }
      return Left(ServerFailure(
        message: "Impossible d'envoyer la photo.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, MaintenanceTicket>> createTicket({
    String? equipmentId,
    required String title,
    String? description,
    String? priority,
    String? assignedToEmail,
    List<String> photoDocumentIds = const [],
  }) async {
    try {
      final dto = await _api.createTicket(
        equipmentId: equipmentId,
        title: title,
        description: description,
        priority: priority,
        assignedToEmail: assignedToEmail,
        photoDocumentIds: photoDocumentIds,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Équipement introuvable.'));
      }
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(message: 'Ticket invalide.'));
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le ticket.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
