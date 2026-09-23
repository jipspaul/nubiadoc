// #7158 — CRUD des modèles de questionnaire côté cabinet : sérialisation du
// schéma (types, options, condition) et mapping des erreurs.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_data/src/remote/questionnaire_templates/questionnaire_template_api.dart';
import 'package:nubia_data/src/remote/questionnaire_templates/questionnaire_template_dto.dart';
import 'package:nubia_data/src/repositories/questionnaire_template_repository_impl.dart';
import 'package:nubia_domain/src/entities/questionnaire_question.dart';
import 'package:nubia_domain/src/error/failure.dart';

class MockQuestionnaireTemplateApi extends Mock
    implements QuestionnaireTemplateApi {}

DioException _dioError(int status) => DioException(
      requestOptions: RequestOptions(path: '/v1/cabinet/questionnaire-templates'),
      response: Response(
        requestOptions:
            RequestOptions(path: '/v1/cabinet/questionnaire-templates'),
        statusCode: status,
      ),
    );

void main() {
  late MockQuestionnaireTemplateApi api;
  late QuestionnaireTemplateRepositoryImpl repo;

  setUp(() {
    api = MockQuestionnaireTemplateApi();
    repo = QuestionnaireTemplateRepositoryImpl(api);
    registerFallbackValue(<QuestionnaireQuestionDto>[]);
  });

  const schema = [
    QuestionnaireQuestion(
      key: 'diabete',
      type: QuestionnaireQuestionType.boolean,
      label: 'Diabète ?',
    ),
    QuestionnaireQuestion(
      key: 'diabete_type',
      type: QuestionnaireQuestionType.select,
      label: 'Type de diabète',
      options: ['Type 1', 'Type 2'],
      condition: QuestionnaireCondition(key: 'diabete', equals: true),
      required: true,
      safetyFlag: true,
    ),
  ];

  test('create sérialise le schéma en JSON snake_case avec la condition',
      () async {
    when(() => api.create(title: any(named: 'title'), schema: any(named: 'schema')))
        .thenAnswer((_) async => (id: 'tpl-1', version: 1));

    final result = await repo.create(title: 'Mon modèle', schema: schema);

    expect(result.fold((_) => null, (r) => r.id), 'tpl-1');
    final captured = verify(() => api.create(
          title: 'Mon modèle',
          schema: captureAny(named: 'schema'),
        )).captured.single as List<QuestionnaireQuestionDto>;
    expect(captured, hasLength(2));
    final conditional = captured[1].toJson();
    expect(conditional['type'], 'select');
    expect(conditional['options'], ['Type 1', 'Type 2']);
    expect(conditional['condition'], {'key': 'diabete', 'equals': true});
    expect(conditional['required'], isTrue);
    expect(conditional['safety_flag'], isTrue);
  });

  test('create — 409 (modèle déjà existant) → ServerFailure statusCode 409',
      () async {
    when(() => api.create(title: any(named: 'title'), schema: any(named: 'schema')))
        .thenThrow(_dioError(409));

    final result = await repo.create(title: 'Mon modèle', schema: schema);

    expect(
      result.fold((f) => f, (_) => null),
      isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 409),
    );
  });

  test('patch délègue id/title/schema et retourne la nouvelle version',
      () async {
    when(() => api.patch(
          any(),
          title: any(named: 'title'),
          schema: any(named: 'schema'),
        )).thenAnswer((_) async => (id: 'tpl-2', version: 2));

    final result = await repo.patch('tpl-1', title: 'Titre modifié');

    expect(result.fold((_) => null, (r) => r.version), 2);
    verify(() => api.patch('tpl-1', title: 'Titre modifié', schema: null))
        .called(1);
  });

  test('patch — 404 → NotFoundFailure', () async {
    when(() => api.patch(
          any(),
          title: any(named: 'title'),
          schema: any(named: 'schema'),
        )).thenThrow(_dioError(404));

    final result = await repo.patch('tpl-1', title: 'x');

    expect(result.fold((f) => f, (_) => null), isA<NotFoundFailure>());
  });

  test('delete délègue l\'id à l\'API', () async {
    when(() => api.delete('tpl-1')).thenAnswer((_) async {});

    await repo.delete('tpl-1');

    verify(() => api.delete('tpl-1')).called(1);
  });

  test('list mappe global/cabinet et round-trippe le schéma', () async {
    when(() => api.list()).thenAnswer((_) async => [
          QuestionnaireTemplateDto.fromJson({
            'id': 'tpl-1',
            'title': 'Standard',
            'version': 1,
            'is_global': true,
            'created_at': '2026-01-01T00:00:00Z',
            'schema': [
              {
                'key': 'allergies',
                'type': 'text',
                'label': 'Allergies',
                'safety_flag': false,
                'required': false,
              },
            ],
          }),
        ]);

    final result = await repo.list();

    final templates = result.fold((_) => null, (t) => t);
    expect(templates, hasLength(1));
    expect(templates!.single.isGlobal, isTrue);
    expect(templates.single.schema.single.type, QuestionnaireQuestionType.text);
  });
}
