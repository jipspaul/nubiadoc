import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/message.dart';
import 'package:nubia_patient/domain/repositories/message_repository.dart';

@injectable
class GetConversationsUseCase {
  final MessageRepository _repository;

  const GetConversationsUseCase(this._repository);

  Future<Either<Failure, List<Conversation>>> call() =>
      _repository.getConversations();
}
