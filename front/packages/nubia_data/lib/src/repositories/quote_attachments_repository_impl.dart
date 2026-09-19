import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/quote_attachments/quote_attachments_api.dart';
import 'package:nubia_domain/src/entities/quote_attachment.dart';
import 'package:nubia_domain/src/repositories/quote_attachments_repository.dart';

class QuoteAttachmentsRepositoryImpl implements QuoteAttachmentsRepository {
  final QuoteAttachmentsApi _api;

  const QuoteAttachmentsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<QuoteAttachment>>> list(String quoteId) async {
    try {
      final dtos = await _api.list(quoteId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Devis introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les pièces jointes.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, QuoteAttachment>> create(
    String quoteId, {
    required QuoteAttachmentKind kind,
    String? documentId,
    String? templateRef,
  }) async {
    try {
      final dto = await _api.create(
        quoteId,
        kind: kind.toApi(),
        documentId: documentId,
        templateRef: templateRef,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapWriteError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> delete(
    String quoteId,
    String attachmentId,
  ) async {
    try {
      await _api.delete(quoteId, attachmentId);
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapWriteError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  Failure _mapWriteError(DioException e) {
    final statusCode = e.response?.statusCode;
    final apiCode = e.response?.data is Map
        ? (e.response!.data as Map)['code'] as String?
        : null;
    if (statusCode == 404) {
      return const NotFoundFailure('Devis ou pièce jointe introuvable.');
    }
    if (statusCode == 401) {
      return const UnauthorizedFailure();
    }
    if (statusCode == 409 && apiCode == 'quote_locked') {
      return const ServerFailure(
        message:
            'Le devis est déjà signé, ses pièces jointes sont verrouillées.',
        statusCode: 409,
        code: 'quote_locked',
      );
    }
    if (statusCode == 422) {
      return const ValidationFailure(
        message: 'Pièce jointe invalide.',
      );
    }
    return ServerFailure(
      message: 'Opération impossible sur les pièces jointes.',
      statusCode: statusCode,
      code: apiCode,
    );
  }
}
