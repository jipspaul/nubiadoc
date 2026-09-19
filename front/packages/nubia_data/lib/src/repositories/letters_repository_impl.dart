import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_data/src/remote/letters/letters_api.dart';
import 'package:nubia_domain/src/entities/generated_letter.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/letters_repository.dart';

class LettersRepositoryImpl implements LettersRepository {
  final LettersApi _api;

  const LettersRepositoryImpl(this._api);

  @override
  Future<Either<Failure, GeneratedLetter>> generate(
    String patientId, {
    required String templateId,
    Map<String, String> overrides = const {},
  }) async {
    try {
      final dto = await _api.generate(
        patientId,
        templateId: templateId,
        overrides: overrides,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (statusCode == 404) {
        return const Left(
          NotFoundFailure('Patient ou modèle de courrier introuvable.'),
        );
      }
      if (statusCode == 422) {
        return Left(_validationFailure(e.response?.data));
      }
      return Left(ServerFailure(
        message: 'Impossible de générer le courrier.',
        statusCode: statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  /// `422 unknown_placeholders`/`missing_placeholder_values` (`api/src/letters.rs`)
  /// portent la liste concernée dans `{"placeholders": [...]}` — reprise en
  /// `fieldErrors` pour que l'écran signale les champs en cause.
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
    return const ValidationFailure(message: 'Courrier invalide.');
  }
}
