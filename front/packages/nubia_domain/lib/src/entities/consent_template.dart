import 'package:equatable/equatable.dart';

/// Modèle de consentement éclairé réutilisable (`consent_template`,
/// #7200/#7199) : catalogue global seedé (`isGlobal`, lecture seule) ou
/// variante propre au cabinet (éditable). Source :
/// `GET /v1/cabinet/consent-templates`.
class ConsentTemplate extends Equatable {
  final String id;
  final String actCategory;
  final String title;
  final String bodyMarkdown;
  final int version;
  final bool isGlobal;
  final DateTime createdAt;

  const ConsentTemplate({
    required this.id,
    required this.actCategory,
    required this.title,
    required this.bodyMarkdown,
    required this.version,
    required this.isGlobal,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id];
}
