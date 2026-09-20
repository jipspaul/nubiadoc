import 'package:nubia_domain/src/entities/quote_event.dart';

class QuoteEventDto {
  final String kind;
  final String at;

  const QuoteEventDto({required this.kind, required this.at});

  factory QuoteEventDto.fromJson(Map<String, dynamic> json) => QuoteEventDto(
        kind: json['kind'] as String,
        at: json['at'] as String,
      );

  QuoteEvent toDomain() => QuoteEvent(
        kind: QuoteEventKind.fromApi(kind),
        at: DateTime.parse(at),
      );
}
