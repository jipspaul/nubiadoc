import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_conversation.dart';
import 'package:nubia_domain/src/entities/conversation_appointment_conversion.dart';
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
    } catch (e) {
      return const Left(ParseFailure());
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
    } catch (e) {
      return const Left(ParseFailure());
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
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ConversationAppointmentConversion>>
      convertToAppointment({
    required String conversationId,
    required String slotId,
  }) async {
    try {
      final dto = await _api.convertToAppointment(
        conversationId: conversationId,
        slotId: slotId,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final apiCode = e.response?.data is Map
          ? (e.response!.data as Map)['code'] as String?
          : null;
      if (statusCode == 409 && apiCode == 'slot_taken') {
        return const Left(ValidationFailure(
          message: 'Ce créneau vient d\'être réservé, choisissez-en un autre.',
        ));
      }
      if (statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      return Left(
          _mapDioError(e, 'Erreur lors de la conversion en rendez-vous.'));
    } catch (e) {
      return const Left(ParseFailure());
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
