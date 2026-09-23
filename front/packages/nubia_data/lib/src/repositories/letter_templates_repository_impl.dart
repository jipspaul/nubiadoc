import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/letter_templates/letter_templates_api.dart';
import 'package:nubia_domain/src/entities/letter_template.dart';
import 'package:nubia_domain/src/entities/letter_template_import_result.dart';
import 'package:nubia_domain/src/repositories/letter_templates_repository.dart';

class LetterTemplatesRepositoryImpl implements LetterTemplatesRepository {
  final LetterTemplatesApi _api;

  const LetterTemplatesRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<LetterTemplate>>> list() async {
    try {
      final dtos = await _api.list();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les modèles de courrier.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, LetterTemplateImportResult>> importDocx({
    required String name,
    required String kind,
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final dto = await _api.import(
        name: name,
        kind: kind,
        bytes: bytes,
        filename: filename,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (statusCode == 422) {
        return Left(_validationFailure(e.response?.data));
      }
      return Left(ServerFailure(
        message: "Impossible d'importer le modèle.",
        statusCode: statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  /// `422 unknown_placeholders` (`api/src/letters.rs`) porte la liste
  /// concernée dans `{"placeholders": [...]}` — même contrat que
  /// `LettersRepositoryImpl._validationFailure`.
  ValidationFailure _validationFailure(dynamic data) {
    if (data is Map<String, dynamic>) {
      final code = data['code'] as String?;
      final placeholders = (data['placeholders'] as List<dynamic>?)
          ?.map((p) => p as String)
          .toList();
      if (placeholders != null && placeholders.isNotEmpty) {
        final label = code == 'unknown_placeholders'
            ? 'Placeholder(s) inconnu(s)'
            : 'Champ(s) requis';
        return ValidationFailure(
          message: '$label : ${placeholders.join(', ')}',
          fieldErrors: {for (final p in placeholders) p: label},
        );
      }
    }
    return const ValidationFailure(message: 'Modèle invalide.');
  }
}
