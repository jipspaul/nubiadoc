import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_conversation.dart';
import 'package:nubia_domain/src/entities/message.dart';
import 'package:nubia_domain/src/repositories/cabinet_message_repository.dart';
import '../remote/cabinet_messaging/cabinet_messaging_api.dart';

class CabinetMessageRepositoryImpl implements CabinetMessageRepository {
  final CabinetMessagingApi _api;

  const CabinetMessageRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<CabinetConversation>>> getConversations() async {
    try {
      final dtos = await _api.getConversations();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(
          _mapDioError(e, 'Erreur lors du chargement des conversations.'));
    }
  }

  @override
  Future<Either<Failure, List<Message>>> getMessages(
      String conversationId) async {
    try {
      final dtos = await _api.getMessages(conversationId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des messages.'));
    }
  }

  @override
  Future<Either<Failure, Message>> send({
    required String conversationId,
    required String text,
    List<String> attachmentIds = const [],
  }) async {
    try {
      final dto = await _api.send(
        conversationId: conversationId,
        text: text,
        attachmentIds: attachmentIds,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors de l\'envoi du message.'));
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
