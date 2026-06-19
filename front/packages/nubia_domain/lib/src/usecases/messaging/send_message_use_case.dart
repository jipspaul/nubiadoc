import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/message.dart';
import 'package:nubia_domain/src/repositories/message_repository.dart';

/// Maximum attachment file size accepted by the API (10 MB).
const int kMaxAttachmentSizeBytes = 10 * 1024 * 1024;

class SendMessageUseCase {
  final MessageRepository _repository;

  const SendMessageUseCase(this._repository);

  /// Sends a message in [conversationId].
  ///
  /// [attachmentFileSizeBytes] — when provided, validated against
  /// [kMaxAttachmentSizeBytes] before the network call. Returns
  /// [ValidationFailure] when the attachment is too large.
  Future<Either<Failure, Message>> call({
    required String conversationId,
    required String text,
    List<String> attachmentIds = const [],
    int? attachmentFileSizeBytes,
  }) {
    if (attachmentFileSizeBytes != null &&
        attachmentFileSizeBytes > kMaxAttachmentSizeBytes) {
      return Future.value(
        const Left(
          ValidationFailure(
            message: 'La pièce jointe dépasse la taille maximale autorisée (10 Mo).',
          ),
        ),
      );
    }
    return _repository.send(
      conversationId: conversationId,
      text: text,
      attachmentIds: attachmentIds,
    );
  }
}
