import 'package:equatable/equatable.dart';

/// Un cycle de stérilisation (#4138). Source :
/// `GET /v1/cabinet/sterilization-cycles`.
class SterilizationCycle extends Equatable {
  final String id;
  final String autoclaveRef;
  final int cycleNumber;
  final DateTime startedAt;
  final String testKind;
  final String testResult;
  final String status;

  const SterilizationCycle({
    required this.id,
    required this.autoclaveRef,
    required this.cycleNumber,
    required this.startedAt,
    required this.testKind,
    required this.testResult,
    required this.status,
  });

  @override
  List<Object?> get props => [id];
}
