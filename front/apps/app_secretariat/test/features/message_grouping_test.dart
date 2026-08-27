//! Tests unitaires : `isMessageContinuation` (#5126) — décision pure de
//! regroupement des messages consécutifs, indépendante du rendu widget.

import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/cabinet_team_messages/message_grouping.dart';

CabinetTeamMessage _message({
  required String senderId,
  required DateTime createdAt,
}) =>
    CabinetTeamMessage(
      id: 'm',
      senderId: senderId,
      senderName: 'Sender',
      body: 'Corps.',
      createdAt: createdAt,
    );

void main() {
  test('pas de message précédent → pas une continuation', () {
    final message = _message(senderId: 'u1', createdAt: DateTime(2026, 1, 1));

    expect(isMessageContinuation(message, null), isFalse);
  });

  test('même auteur, même jour → continuation', () {
    final previous = _message(
      senderId: 'u1',
      createdAt: DateTime(2026, 1, 1, 8, 20),
    );
    final message = _message(
      senderId: 'u1',
      createdAt: DateTime(2026, 1, 1, 8, 24),
    );

    expect(isMessageContinuation(message, previous), isTrue);
  });

  test('auteur différent, même jour → pas une continuation', () {
    final previous = _message(
      senderId: 'u1',
      createdAt: DateTime(2026, 1, 1, 8, 20),
    );
    final message = _message(
      senderId: 'u2',
      createdAt: DateTime(2026, 1, 1, 8, 24),
    );

    expect(isMessageContinuation(message, previous), isFalse);
  });

  test('même auteur, jour différent → pas une continuation', () {
    final previous = _message(
      senderId: 'u1',
      createdAt: DateTime(2026, 1, 1, 23, 50),
    );
    final message = _message(
      senderId: 'u1',
      createdAt: DateTime(2026, 1, 2, 0, 5),
    );

    expect(isMessageContinuation(message, previous), isFalse);
  });
}
