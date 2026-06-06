import 'package:dartz/dartz.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/message.dart';

abstract class MessageRepository {
  Future<Either<Failure, List<Conversation>>> getConversations();
  Future<Either<Failure, List<Message>>> getMessages(String conversationId);
  Future<Either<Failure, Message>> send({
    required String conversationId,
    required String text,
    List<String> attachmentIds = const [],
  });
  Future<Either<Failure, void>> markRead(String conversationId);

  /// Uploads a photo as a document attachment.
  ///
  /// Returns the newly created document ID which can be passed as an
  /// `attachmentId` when calling [send].
  Future<Either<Failure, String>> uploadAttachment({
    required String filePath,
    required String filename,
    required String mimeType,
  });
}
