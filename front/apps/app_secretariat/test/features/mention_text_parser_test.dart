//! Tests unitaires : `parseMentionSegments` (#5129) — parsing pur des
//! mentions `@Nom` dans le corps d'un message, indépendant du rendu widget.

import 'package:flutter_test/flutter_test.dart';

import 'package:app_secretariat/features/cabinet_team_messages/mention_text_parser.dart';

void main() {
  test('corps sans mention → un seul segment texte', () {
    final segments = parseMentionSegments('Réunion à 12h30.');

    expect(segments, hasLength(1));
    expect(segments.single.isMention, isFalse);
    expect(segments.single.text, 'Réunion à 12h30.');
  });

  test('mention en milieu de phrase → 3 segments texte/mention/texte', () {
    final segments = parseMentionSegments('@Sarah tu peux la contacter ?');

    expect(segments, hasLength(2));
    expect(segments[0].isMention, isTrue);
    expect(segments[0].text, '@Sarah');
    expect(segments[1].isMention, isFalse);
    expect(segments[1].text, ' tu peux la contacter ?');
  });

  test('mention avec texte avant et après', () {
    final segments =
        parseMentionSegments('Message pour @Sarah avant midi.');

    expect(segments, hasLength(3));
    expect(segments[0], isA<MentionTextSegment>());
    expect(segments[0].isMention, isFalse);
    expect(segments[0].text, 'Message pour ');
    expect(segments[1].isMention, isTrue);
    expect(segments[1].text, '@Sarah');
    expect(segments[2].isMention, isFalse);
    expect(segments[2].text, ' avant midi.');
  });

  test('plusieurs mentions dans le même message', () {
    final segments = parseMentionSegments('@Sarah et @Marc, une idée ?');

    final mentions = segments.where((s) => s.isMention).map((s) => s.text);
    expect(mentions, ['@Sarah', '@Marc']);
  });

  test('mention avec accent dans le nom', () {
    final segments = parseMentionSegments('@Amélie peux-tu vérifier ?');

    expect(segments.first.isMention, isTrue);
    expect(segments.first.text, '@Amélie');
  });
}
