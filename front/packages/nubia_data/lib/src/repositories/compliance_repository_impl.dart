import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_data/src/remote/compliance/compliance_api.dart';
import 'package:nubia_domain/src/entities/compliance_item.dart';
import 'package:nubia_domain/src/entities/custom_device_declaration_result.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/compliance_repository.dart';

class ComplianceRepositoryImpl implements ComplianceRepository {
  final ComplianceApi _api;

  const ComplianceRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<ComplianceItem>>> listItems() async {
    try {
      final dtos = await _api.listItems();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger l'échéancier de conformité.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> createItem({
    required String kind,
    required String label,
    String? subjectUserId,
    String? equipmentLabel,
    required String dueDate,
    int? recurrenceMonths,
  }) async {
    try {
      final id = await _api.createItem(
        kind: kind,
        label: label,
        subjectUserId: subjectUserId,
        equipmentLabel: equipmentLabel,
        dueDate: dueDate,
        recurrenceMonths: recurrenceMonths,
      );
      return Right(id);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(message: 'Item invalide.'));
      }
      return Left(ServerFailure(
        message: "Impossible de créer l'item de conformité.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> completeItem(String itemId) async {
    try {
      final status = await _api.complete(itemId);
      return Right(status);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      // 409 invalid_status : l'item est déjà clôturé.
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Cet item a déjà été clôturé.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: "Impossible de clôturer l'item de conformité.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ComplianceItem>> attachEvidence({
    required String itemId,
    required String evidenceDocumentId,
  }) async {
    try {
      final dto = await _api.attachEvidence(
        itemId,
        evidenceDocumentId: evidenceDocumentId,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Cet item a déjà été clôturé.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de rattacher le justificatif.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CustomDeviceDeclarationResult>> declareCustomDevice({
    required String patientId,
    required String labName,
    required String deviceDescription,
    String? consultationActId,
  }) async {
    try {
      final dto = await _api.declareCustomDevice(
        patientId,
        labName: labName,
        deviceDescription: deviceDescription,
        consultationActId: consultationActId,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(message: 'Déclaration invalide.'));
      }
      return Left(ServerFailure(
        message: 'Impossible de générer la déclaration DMSM.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
