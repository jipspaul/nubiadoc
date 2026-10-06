import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_correspondents/cabinet_correspondents_api.dart';
import 'package:nubia_domain/src/entities/cabinet_correspondent.dart';
import 'package:nubia_domain/src/repositories/cabinet_correspondents_repository.dart';

/// Message par champ (#8064) pour un `422 {"code":"validation_error","field":…}`
/// — avant ce correctif, tous les 422 recevaient le même message générique
/// accusant le nom, même quand lui seul était valide.
const _kFieldValidationMessages = <String, String>{
  'display_name':
      'Le nom du correspondant est obligatoire ou dépasse la longueur autorisée.',
  'specialty': 'La spécialité dépasse la longueur autorisée.',
  'email': "L'adresse e-mail n'est pas valide.",
  'phone': 'Le téléphone dépasse la longueur autorisée.',
  'address': "L'adresse dépasse la longueur autorisée.",
  'rpps': 'Le RPPS dépasse la longueur autorisée.',
  'notes': 'Les notes dépassent la longueur autorisée.',
};

String _correspondentValidationMessage(DioException e) {
  final data = e.response?.data;
  final field = data is Map ? data['field'] : null;
  return _kFieldValidationMessages[field] ??
      'Le nom du correspondant est obligatoire ou un champ est invalide.';
}

class CabinetCorrespondentsRepositoryImpl
    implements CabinetCorrespondentsRepository {
  final CabinetCorrespondentsApi _api;

  const CabinetCorrespondentsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<CabinetCorrespondent>>> list() async {
    try {
      final dtos = await _api.list();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les correspondants.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetCorrespondent>> create({
    required String displayName,
    String? specialty,
    String? email,
    String? phone,
    String? address,
    String? rpps,
    String? notes,
  }) async {
    try {
      final dto = await _api.create(
        displayName: displayName,
        specialty: specialty,
        email: email,
        phone: phone,
        address: address,
        rpps: rpps,
        notes: notes,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return Left(
          ValidationFailure(message: _correspondentValidationMessage(e)),
        );
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le correspondant.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetCorrespondent>> update(
    String id, {
    String? displayName,
    String? specialty,
    String? email,
    String? phone,
    String? address,
    String? rpps,
    String? notes,
  }) async {
    try {
      final dto = await _api.update(
        id,
        displayName: displayName,
        specialty: specialty,
        email: email,
        phone: phone,
        address: address,
        rpps: rpps,
        notes: notes,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return Left(
          ValidationFailure(message: _correspondentValidationMessage(e)),
        );
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Correspondant introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de modifier le correspondant.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> delete(String id) async {
    try {
      await _api.delete(id);
      return const Right(null);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Ce correspondant est référencé par au moins un patient '
              'ou un courrier : impossible de le supprimer.',
          statusCode: 409,
          code: 'correspondent_in_use',
        ));
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Correspondant introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de supprimer le correspondant.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CorrespondentStats>> getStats(String id) async {
    try {
      final dto = await _api.getStats(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Correspondant introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les statistiques du correspondant.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
