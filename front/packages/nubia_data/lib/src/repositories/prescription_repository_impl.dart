import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/prescriptions/prescription_api.dart';
import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/entities/prescription_template.dart';
import 'package:nubia_domain/src/repositories/prescription_repository.dart';

class PrescriptionRepositoryImpl implements PrescriptionRepository {
  final PrescriptionApi _api;

  const PrescriptionRepositoryImpl(this._api);

  @override
  Future<Either<Failure, Prescription>> createPrescription({
    required String patientId,
    required List<PrescriptionItem> items,
  }) async {
    try {
      final dto = await _api.createPrescription(
        patientId: patientId,
        items: items,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de créer l'ordonnance.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Prescription>> signPrescription(String id) async {
    try {
      final dto = await _api.signPrescription(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de signer l'ordonnance.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Prescription>> sendToPharmacy({
    required String prescriptionId,
    required String pharmacyId,
  }) async {
    try {
      final dto = await _api.sendToPharmacy(
        prescriptionId: prescriptionId,
        pharmacyId: pharmacyId,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible d'envoyer l'ordonnance à la pharmacie.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<PrescriptionTemplate>>>
      listPrescriptionTemplates() async {
    try {
      final dtos = await _api.listPrescriptionTemplates();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les modèles.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Prescription>> applyPrescriptionTemplate({
    required String prescriptionId,
    required String templateId,
  }) async {
    try {
      await _api.applyPrescriptionTemplate(
        prescriptionId: prescriptionId,
        templateId: templateId,
      );
      // apply-template ne renvoie que le nombre de lignes créées : re-fetch
      // pour obtenir l'ordonnance avec ses lignes à jour.
      final dto = await _api.getPrescription(prescriptionId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible d'appliquer le modèle.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<Prescription>>> listPrescriptions(
    String patientId,
  ) async {
    try {
      final dtos = await _api.listPrescriptions(patientId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger l'historique des ordonnances.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Prescription>> renewPrescription(
    String prescriptionId,
  ) async {
    try {
      final newId = await _api.renewPrescription(prescriptionId);
      // renew ne renvoie que l'id créé : re-fetch pour l'ordonnance complète,
      // même pattern que applyPrescriptionTemplate.
      final dto = await _api.getPrescription(newId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de renouveler l'ordonnance.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
