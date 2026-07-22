import 'package:equatable/equatable.dart';

/// A cabinet-owned report template (`cr_template`, #4123/#4124).
/// `ccamCode` : `null` for a generic template, or the CCAM code it's
/// pre-filled for.
class CrTemplate extends Equatable {
  final String id;
  final String? ccamCode;
  final String title;
  final String bodyTemplate;

  const CrTemplate({
    required this.id,
    this.ccamCode,
    required this.title,
    required this.bodyTemplate,
  });

  @override
  List<Object?> get props => [id, ccamCode, title, bodyTemplate];
}
