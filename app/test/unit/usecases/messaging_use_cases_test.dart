import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/message.dart';
import 'package:nubia_patient/domain/repositories/message_repository.dart';
import 'package:nubia_patient/domain/usecases/messaging/get_conversations_use_case.dart';
import 'package:nubia_patient/domain/usecases/messaging/send_message_use_case.dart';

class MockMessageRepository extends Mock implements MessageRepository {}

Conversation _makeConversation({String id = 'conv1', int unreadCount = 0}) =>
    Conversation(
      id: id,
      cabinetId: 'cab1',
      cabinetName: 'Cabinet Marin',
      unreadCount: unreadCount,
    );

Message _makeMessage({String id = 'msg1'}) => Message(
      id: id,
      conversationId: 'conv1',
      sender: MessageSender.patient,
      text: 'Bonjour',
      urgency: MessageUrgency.normal,
      sentAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockMessageRepository repository;

  setUp(() {
    repository = MockMessageRepository();
  });

  group('GetConversationsUseCase', () {
    late GetConversationsUseCase useCase;

    setUp(() => useCase = GetConversationsUseCase(repository));

    test('returns list of conversations on success', () async {
      final conversations = [
        _makeConversation(id: 'conv1', unreadCount: 2),
        _makeConversation(id: 'conv2', unreadCount: 0),
      ];
      when(() => repository.getConversations())
          .thenAnswer((_) async => Right(conversations));

      final result = await useCase();

      expect(result, Right<Failure, List<Conversation>>(conversations));
      verify(() => repository.getConversations()).called(1);
    });

    test('exposes unread count from conversations', () async {
      final conversations = [
        _makeConversation(id: 'conv1', unreadCount: 5),
      ];
      when(() => repository.getConversations())
          .thenAnswer((_) async => Right(conversations));

      final result = await useCase();

      result.fold(
        (_) => fail('expected success'),
        (list) => expect(list.first.unreadCount, 5),
      );
    });

    test('returns Failure on error', () async {
      when(() => repository.getConversations())
          .thenAnswer((_) async => const Left(OfflineFailure()));

      final result = await useCase();

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<OfflineFailure>()),
        (_) => fail('expected failure'),
      );
    });
  });

  group('SendMessageUseCase', () {
    late SendMessageUseCase useCase;

    setUp(() => useCase = SendMessageUseCase(repository));

    test('returns Message on success', () async {
      final message = _makeMessage();
      when(() => repository.send(
            conversationId: 'conv1',
            text: 'Bonjour',
            attachmentIds: const [],
          )).thenAnswer((_) async => Right(message));

      final result = await useCase(conversationId: 'conv1', text: 'Bonjour');

      expect(result, Right<Failure, Message>(message));
      verify(() => repository.send(
            conversationId: 'conv1',
            text: 'Bonjour',
            attachmentIds: const [],
          )).called(1);
    });

    test('returns ValidationFailure when attachment exceeds 10 MB', () async {
      const oversizedBytes = 10 * 1024 * 1024 + 1;

      final result = await useCase(
        conversationId: 'conv1',
        text: 'Voir en pièce jointe',
        attachmentFileSizeBytes: oversizedBytes,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected ValidationFailure'),
      );
      verifyNever(() => repository.send(
            conversationId: any(named: 'conversationId'),
            text: any(named: 'text'),
          ));
    });

    test('does not reject attachment exactly at 10 MB limit', () async {
      const exactLimitBytes = 10 * 1024 * 1024;
      final message = _makeMessage();
      when(() => repository.send(
            conversationId: any(named: 'conversationId'),
            text: any(named: 'text'),
            attachmentIds: any(named: 'attachmentIds'),
          )).thenAnswer((_) async => Right(message));

      final result = await useCase(
        conversationId: 'conv1',
        text: 'Fichier',
        attachmentFileSizeBytes: exactLimitBytes,
      );

      expect(result.isRight(), isTrue);
    });
  });
}
