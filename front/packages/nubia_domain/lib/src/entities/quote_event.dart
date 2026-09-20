import 'package:equatable/equatable.dart';

/// Jalon d'un devis (`quote_event`, migration 0287). Le CHECK back-end
/// autorise aussi `reminded`/`refused`/`message` : non modélisés ici, la
/// timeline « Suivi » (#7467) ne rend que les 4 étapes de la maquette
/// design-v2 (créé, envoyé, consulté, signé).
enum QuoteEventKind {
  created,
  sent,
  viewed,
  signed,
  unknown;

  static QuoteEventKind fromApi(String value) => switch (value) {
        'created' => QuoteEventKind.created,
        'sent' => QuoteEventKind.sent,
        'viewed' => QuoteEventKind.viewed,
        'signed' => QuoteEventKind.signed,
        _ => QuoteEventKind.unknown,
      };
}

/// Un jalon de la timeline d'un devis. Source :
/// `GET /v1/cabinet/quotes/:id/events`.
class QuoteEvent extends Equatable {
  final QuoteEventKind kind;
  final DateTime at;

  const QuoteEvent({required this.kind, required this.at});

  @override
  List<Object?> get props => [kind, at];
}
