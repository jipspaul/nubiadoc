import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/documents/document_api.dart';
import 'package:nubia_domain/src/entities/document.dart';
import 'package:nubia_domain/src/repositories/document_repository.dart';

class DocumentRepositoryImpl implements DocumentRepository {
  final DocumentApi _api;

  const DocumentRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<Document>>> getAll({
    int? limit,
    String? patientAccount,
  }) async {
    try {
      final dtos = await _api.getAll(limit: limit, patientAccount: patientAccount);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des documents.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<Document>>> getByCategory(
      DocumentCategory category) async {
    try {
      // #8375 : une catégorie client peut recouvrir PLUSIEURS codes API
      // (cf. [_categoryApiCodesFor]) — interroger un seul code sous-compte
      // la catégorie par rapport à [categoryCounts], qui les additionne
      // tous. Les résultats sont fusionnés puis re-triés (chaque requête
      // est triée individuellement par l'API, pas l'union des deux).
      final codes = _categoryApiCodesFor(category);
      final results = await Future.wait(codes.map(_api.getByCategory));
      final dtos = results.expand((dtos) => dtos).toList()
        ..sort((a, b) =>
            DateTime.parse(b.createdAt).compareTo(DateTime.parse(a.createdAt)));
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des documents.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, int>> count({String? patientAccount}) async {
    try {
      final total = await _api.count(patientAccount: patientAccount);
      return Right(total);
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des documents.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Map<DocumentCategory, int>>> categoryCounts({
    String? patientAccount,
  }) async {
    try {
      final counted = await Future.wait(_categoryApiCodes.map((entry) async {
        final total = await _api.count(
          patientAccount: patientAccount,
          category: entry.$1,
        );
        return (entry.$2, total);
      }));
      final counts = <DocumentCategory, int>{};
      for (final (category, total) in counted) {
        counts.update(category, (n) => n + total, ifAbsent: () => total);
      }
      return Right(counts);
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des documents.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, PagedDocuments>> getPage({
    int limit = 20,
    String? cursor,
    String? patientAccount,
  }) async {
    try {
      final page = await _api.getPage(
        limit: limit,
        cursor: cursor,
        patientAccount: patientAccount,
      );
      return Right((
        documents: page.documents.map((d) => d.toDomain()).toList(),
        nextCursor: page.nextCursor,
        total: page.total,
      ));
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des documents.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> getSignedUrl(String documentId) async {
    try {
      final dto = await _api.getSignedUrl(documentId);
      return Right(dto.url);
    } on DioException catch (e) {
      return Left(_mapDioError(
          e, 'Erreur lors de la récupération du lien de téléchargement.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Document>> upload({
    required List<int> bytes,
    required String filename,
    required String mimeType,
    required DocumentCategory category,
    String? patientAccount,
  }) async {
    try {
      final dto = await _api.upload(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
        category: _categoryToApi(category),
        patientAccount: patientAccount,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors de l\'envoi du document.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  /// Catégories API connues et leur [DocumentCategory] — utilisé par
  /// [categoryCounts] pour interroger chaque catégorie séparément. `consigne`
  /// et `attestation` se replient tous deux sur [DocumentCategory.instructions]
  /// (même règle que [DocumentDto.parseCategory]) et leurs comptes s'additionnent.
  /// Les catégories hors de cette liste (ex. courrier, dmsm) ne sont pas
  /// interrogées individuellement : elles composent le reliquat affiché
  /// comme « Autre » (totalCount - somme de ces comptes), calculé côté écran.
  static const _categoryApiCodes = <(String, DocumentCategory)>[
    ('devis', DocumentCategory.quote),
    ('facture', DocumentCategory.invoice),
    ('ordonnance', DocumentCategory.prescription),
    ('radio', DocumentCategory.xray),
    ('cbct', DocumentCategory.cbct),
    ('photo', DocumentCategory.photo),
    ('cr', DocumentCategory.report),
    ('consentement', DocumentCategory.consent),
    ('consigne', DocumentCategory.instructions),
    ('attestation', DocumentCategory.instructions),
    ('carte_mutuelle', DocumentCategory.mutualCard),
    ('carte_vitale', DocumentCategory.vitalCard),
  ];

  /// Catégories API valides (`api/src/documents.rs` VALID_CATEGORIES) sans
  /// correspondance individuelle dans [_categoryApiCodes] — composent le
  /// reliquat affiché comme « Autre » (calculé côté écran, voir
  /// `documents_page.dart` `_facets`). `other` seul n'existe pas côté API :
  /// `list_documents` renvoie alors 0 résultat sans même requêter la base.
  static const _otherApiCodes = ['courrier', 'dmsm', 'passeport_implantaire'];

  /// Codes API à interroger pour [getByCategory] — doit couvrir exactement
  /// les mêmes codes que [categoryCounts] additionne pour cette catégorie
  /// (#8375) : sinon une puce annonce un compte qu'elle n'honore pas (ex.
  /// « Consigne 24 » n'interrogeait que `consigne`, alors que son compte
  /// additionne `consigne` + `attestation`).
  static List<String> _categoryApiCodesFor(DocumentCategory category) {
    if (category == DocumentCategory.other) return _otherApiCodes;
    return [
      for (final entry in _categoryApiCodes)
        if (entry.$2 == category) entry.$1,
    ];
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
      case DocumentCategory.vitalCard:
        return 'carte_vitale';
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
