// #7158 — logique de visibilité conditionnelle (« afficher si ») d'une
// question de questionnaire, pure Dart, testable sans widget.
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

void main() {
  group('QuestionnaireCondition', () {
    test('satisfaite quand la réponse déjà saisie correspond', () {
      const condition = QuestionnaireCondition(key: 'diabete', equals: true);

      expect(condition.isSatisfiedBy({'diabete': true}), isTrue);
      expect(condition.isSatisfiedBy({'diabete': false}), isFalse);
      expect(condition.isSatisfiedBy({}), isFalse);
    });

    test('comparaison stricte — pas de coercition de type', () {
      const condition = QuestionnaireCondition(key: 'type', equals: 'Type 1');

      expect(condition.isSatisfiedBy({'type': 'Type 1'}), isTrue);
      expect(condition.isSatisfiedBy({'type': 'type 1'}), isFalse);
    });
  });

  group('QuestionnaireQuestion.isVisible', () {
    const withoutCondition = QuestionnaireQuestion(
      key: 'allergies',
      type: QuestionnaireQuestionType.text,
      label: 'Allergies',
    );

    const withCondition = QuestionnaireQuestion(
      key: 'diabete_type',
      type: QuestionnaireQuestionType.select,
      label: 'Type de diabète',
      options: ['Type 1', 'Type 2'],
      condition: QuestionnaireCondition(key: 'diabete', equals: true),
    );

    test('toujours visible sans condition', () {
      expect(withoutCondition.isVisible({}), isTrue);
    });

    test('masquée tant que la condition n\'est pas satisfaite', () {
      expect(withCondition.isVisible({}), isFalse);
      expect(withCondition.isVisible({'diabete': false}), isFalse);
    });

    test('révélée une fois la condition satisfaite', () {
      expect(withCondition.isVisible({'diabete': true}), isTrue);
    });

    test('une seule passe — pas de résolution transitive de chaîne', () {
      // B dépend de A, C dépend de B : si seul A est répondu, B est déjà
      // visible mais C reste masquée tant que B n'a pas lui-même de réponse
      // enregistrée dans le payload (cohérent avec `condition_met` côté API,
      // une seule lecture du payload, pas de fixpoint récursif).
      const questionB = QuestionnaireQuestion(
        key: 'b',
        type: QuestionnaireQuestionType.boolean,
        label: 'B',
        condition: QuestionnaireCondition(key: 'a', equals: true),
      );
      const questionC = QuestionnaireQuestion(
        key: 'c',
        type: QuestionnaireQuestionType.text,
        label: 'C',
        condition: QuestionnaireCondition(key: 'b', equals: true),
      );

      final payload = {'a': true};
      expect(questionB.isVisible(payload), isTrue);
      expect(questionC.isVisible(payload), isFalse);
    });
  });
}
