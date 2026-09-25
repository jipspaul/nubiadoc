import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_data/src/remote/provider_stamp/provider_stamp_api.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/provider_stamp_repository.dart';

class ProviderStampRepositoryImpl implements ProviderStampRepository {
  final ProviderStampApi _api;

  const ProviderStampRepositoryImpl(this._api);

  @override
  Future<Either<Failure, String>> uploadSignature({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) =>
      _upload(
        () => _api.uploadSignature(
          bytes: bytes,
          filename: filename,
          mimeType: mimeType,
        ),
        errorMessage: "Impossible d'envoyer la signature.",
      );

  @override
  Future<Either<Failure, String>> uploadStamp({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) =>
      _upload(
        () => _api.uploadStamp(
          bytes: bytes,
          filename: filename,
          mimeType: mimeType,
        ),
        errorMessage: "Impossible d'envoyer le tampon.",
      );

  Future<Either<Failure, String>> _upload(
    Future<String> Function() call, {
    required String errorMessage,
  }) async {
    try {
      final documentId = await call();
      return Right(documentId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(
          NotFoundFailure('Profil praticien introuvable pour ce compte.'),
        );
      }
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(
          message: 'Image invalide — seul le JPEG est accepté.',
        ));
      }
      return Left(ServerFailure(
        message: errorMessage,
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
