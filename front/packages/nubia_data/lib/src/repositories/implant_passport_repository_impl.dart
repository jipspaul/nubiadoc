import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/implant_passport/implant_passport_api.dart';
import 'package:nubia_domain/src/entities/implant_item.dart';
import 'package:nubia_domain/src/repositories/implant_passport_repository.dart';

class ImplantPassportRepositoryImpl implements ImplantPassportRepository {
  final ImplantPassportApi _api;

  const ImplantPassportRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<ImplantItem>>> listPassport() async {
    try {
      final dtos = await _api.listPassport();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le passeport implantaire.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> exportPassport() async {
    try {
      final url = await _api.exportPassport();
      return Right(url);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      // 410 link_expired : le signer de stockage a échoué côté API.
      if (e.response?.statusCode == 410) {
        return const Left(ServerFailure(
          message: "Le lien d'export a expiré, réessayez.",
          statusCode: 410,
        ));
      }
      return Left(ServerFailure(
        message: "Impossible d'exporter le passeport implantaire.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ImplantItem>> createImplant({
    required String patientId,
    required String brand,
    required String implantRef,
    String? lotNumber,
    String? placementDate,
    String? toothPosition,
    String? notes,
  }) async {
    try {
      final id = await _api.createImplant(
        patientId: patientId,
        brand: brand,
        implantRef: implantRef,
        lotNumber: lotNumber,
        placementDate: placementDate,
        toothPosition: toothPosition,
        notes: notes,
      );
      // POST ne renvoie que l'id : reconstruit à partir des valeurs du
      // formulaire déjà connues côté client (pas de re-fetch nécessaire).
      return Right(ImplantItem(
        id: id,
        brand: brand,
        lotNumber: lotNumber,
        placementDate: placementDate,
        toothPosition: toothPosition,
        notes: notes,
      ));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 403) {
        return const Left(ServerFailure(
          message: "Aucune relation de soin avec ce patient.",
          statusCode: 403,
        ));
      }
      return Left(ServerFailure(
        message: "Impossible d'enregistrer l'implant.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
