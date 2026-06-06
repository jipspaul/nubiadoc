import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/data/remote/messaging/messaging_api.dart';
import 'package:nubia_patient/domain/entities/message.dart';
import 'package:nubia_patient/domain/repositories/message_repository.dart';

@LazySingleton(as: MessageRepository)
class MessageRepositoryImpl implements MessageRepository {
  final MessagingApi _api;

  const MessageRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<Conversation>>> getConversations() async {
    try {
      final dtos = await _api.getConversations();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des conversations.'));
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

  @override
  Future<Either<Failure, void>> markRead(String conversationId) async {
    try {
      await _api.markRead(conversationId);
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du marquage comme lu.'));
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
