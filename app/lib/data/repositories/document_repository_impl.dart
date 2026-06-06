import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/data/remote/documents/document_api.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/domain/repositories/document_repository.dart';

@LazySingleton(as: DocumentRepository)
class DocumentRepositoryImpl implements DocumentRepository {
  final DocumentApi _api;

  const DocumentRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<Document>>> getAll() async {
    try {
      final dtos = await _api.getAll();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des documents.'));
    }
  }

  @override
  Future<Either<Failure, List<Document>>> getByCategory(
      DocumentCategory category) async {
    try {
      final raw = _categoryToApi(category);
      final dtos = await _api.getByCategory(raw);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des documents.'));
    }
  }

  @override
  Future<Either<Failure, String>> getSignedUrl(String documentId) async {
    try {
      final dto = await _api.getSignedUrl(documentId);
      return Right(dto.url);
    } on DioException catch (e) {
      return Left(
          _mapDioError(e, 'Erreur lors de la récupération du lien de téléchargement.'));
    }
  }

  @override
  Future<Either<Failure, Document>> upload({
    required String filePath,
    required String filename,
    required String mimeType,
    required DocumentCategory category,
  }) async {
    try {
      final dto = await _api.upload(
        filePath: filePath,
        filename: filename,
        mimeType: mimeType,
        category: _categoryToApi(category),
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors de l\'envoi du document.'));
    }
  }

  static String _categoryToApi(DocumentCategory category) {
    switch (category) {
      case DocumentCategory.quote:
        return 'devis';
      case DocumentCategory.invoice:
        return 'facture';
      case DocumentCategory.prescription:
        return 'ordonnance';
      case DocumentCategory.xray:
        return 'radio';
      case DocumentCategory.cbct:
        return 'cbct';
      case DocumentCategory.photo:
        return 'photo';
      case DocumentCategory.report:
        return 'cr';
      case DocumentCategory.consent:
        return 'consentement';
      case DocumentCategory.instructions:
        return 'consigne';
      case DocumentCategory.mutualCard:
        return 'carte_mutuelle';
      case DocumentCategory.other:
        return 'other';
    }
  }

  Failure _mapDioError(DioException e, String defaultMessage) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const OfflineFailure();
    }
    if (e.response?.statusCode == 401) {
      return const UnauthorizedFailure();
    }
    return ServerFailure(
      message: defaultMessage,
      statusCode: e.response?.statusCode,
    );
  }
}
