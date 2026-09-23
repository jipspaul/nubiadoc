import 'package:nubia_domain/src/entities/questionnaire_question.dart';
import 'package:nubia_domain/src/entities/questionnaire_template.dart';

class QuestionnaireConditionDto {
  final String key;
  final dynamic equals;

  const QuestionnaireConditionDto({required this.key, required this.equals});

  factory QuestionnaireConditionDto.fromJson(Map<String, dynamic> json) =>
      QuestionnaireConditionDto(
        key: json['key'] as String,
        equals: json['equals'],
      );

  factory QuestionnaireConditionDto.fromDomain(
    QuestionnaireCondition condition,
  ) =>
      QuestionnaireConditionDto(key: condition.key, equals: condition.equals);

  Map<String, dynamic> toJson() => {'key': key, 'equals': equals};

  QuestionnaireCondition toDomain() =>
      QuestionnaireCondition(key: key, equals: equals);
}

class QuestionnaireQuestionDto {
  final String key;
  final String type;
  final String label;
  final List<String> options;
  final QuestionnaireConditionDto? condition;
  final bool safetyFlag;
  final bool required;

  const QuestionnaireQuestionDto({
    required this.key,
    required this.type,
    required this.label,
    this.options = const [],
    this.condition,
    this.safetyFlag = false,
    this.required = false,
  });

  factory QuestionnaireQuestionDto.fromJson(Map<String, dynamic> json) {
    final conditionJson = json['condition'] as Map<String, dynamic>?;
    return QuestionnaireQuestionDto(
      key: json['key'] as String,
      type: json['type'] as String,
      label: json['label'] as String,
      options:
          (json['options'] as List<dynamic>? ?? const []).cast<String>(),
      condition: conditionJson != null
          ? QuestionnaireConditionDto.fromJson(conditionJson)
          : null,
      safetyFlag: json['safety_flag'] as bool? ?? false,
      required: json['required'] as bool? ?? false,
    );
  }

  factory QuestionnaireQuestionDto.fromDomain(QuestionnaireQuestion q) =>
      QuestionnaireQuestionDto(
        key: q.key,
        type: _typeToString(q.type),
        label: q.label,
        options: q.options,
        condition: q.condition != null
            ? QuestionnaireConditionDto.fromDomain(q.condition!)
            : null,
        safetyFlag: q.safetyFlag,
        required: q.required,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type,
        'label': label,
        if (options.isNotEmpty) 'options': options,
        if (condition != null) 'condition': condition!.toJson(),
        'safety_flag': safetyFlag,
        'required': required,
      };

  QuestionnaireQuestion toDomain() => QuestionnaireQuestion(
        key: key,
        type: _typeFromString(type),
        label: label,
        options: options,
        condition: condition?.toDomain(),
        safetyFlag: safetyFlag,
        required: required,
      );

  static QuestionnaireQuestionType _typeFromString(String value) {
    switch (value) {
      case 'boolean':
        return QuestionnaireQuestionType.boolean;
      case 'select':
        return QuestionnaireQuestionType.select;
      default:
        return QuestionnaireQuestionType.text;
    }
  }

  static String _typeToString(QuestionnaireQuestionType type) {
    switch (type) {
      case QuestionnaireQuestionType.boolean:
        return 'boolean';
      case QuestionnaireQuestionType.select:
        return 'select';
      case QuestionnaireQuestionType.text:
        return 'text';
    }
  }
}

class QuestionnaireTemplateDto {
  final String id;
  final String title;
  final List<QuestionnaireQuestionDto> schema;
  final int version;
  final bool isGlobal;
  final DateTime createdAt;

  const QuestionnaireTemplateDto({
    required this.id,
    required this.title,
    required this.schema,
    required this.version,
    required this.isGlobal,
    required this.createdAt,
  });

  factory QuestionnaireTemplateDto.fromJson(Map<String, dynamic> json) =>
      QuestionnaireTemplateDto(
        id: json['id'] as String,
        title: json['title'] as String,
        schema: (json['schema'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(QuestionnaireQuestionDto.fromJson)
            .toList(),
        version: json['version'] as int,
        isGlobal: json['is_global'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  QuestionnaireTemplate toDomain() => QuestionnaireTemplate(
        id: id,
        title: title,
        schema: schema.map((q) => q.toDomain()).toList(),
        version: version,
        isGlobal: isGlobal,
        createdAt: createdAt,
      );
}

/// `GET /v1/account/medical-questionnaire/active-template` — pas de
/// [isGlobal] ni [createdAt] dans la réponse patient (`ActiveQuestionnaireTemplateResponse`
/// côté API), contrairement au DTO praticien ci-dessus.
class ActiveQuestionnaireTemplateDto {
  final String templateId;
  final int version;
  final String title;
  final List<QuestionnaireQuestionDto> schema;

  const ActiveQuestionnaireTemplateDto({
    required this.templateId,
    required this.version,
    required this.title,
    required this.schema,
  });

  factory ActiveQuestionnaireTemplateDto.fromJson(Map<String, dynamic> json) =>
      ActiveQuestionnaireTemplateDto(
        templateId: json['template_id'] as String,
        version: json['version'] as int,
        title: json['title'] as String,
        schema: (json['schema'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(QuestionnaireQuestionDto.fromJson)
            .toList(),
      );

  QuestionnaireTemplate toDomain() => QuestionnaireTemplate(
        id: templateId,
        title: title,
        schema: schema.map((q) => q.toDomain()).toList(),
        version: version,
      );
}
