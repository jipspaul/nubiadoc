import 'package:nubia_domain/src/entities/sterilization_cycle.dart';

class SterilizationCycleDto {
  final String id;
  final String autoclaveRef;
  final int cycleNumber;
  final String startedAt;
  final String testKind;
  final String testResult;
  final String status;

  const SterilizationCycleDto({
    required this.id,
    required this.autoclaveRef,
    required this.cycleNumber,
    required this.startedAt,
    required this.testKind,
    required this.testResult,
    required this.status,
  });

  factory SterilizationCycleDto.fromJson(Map<String, dynamic> json) =>
      SterilizationCycleDto(
        id: json['id'] as String,
        autoclaveRef: json['autoclave_ref'] as String,
        cycleNumber: json['cycle_number'] as int,
        startedAt: json['started_at'] as String,
        testKind: json['test_kind'] as String,
        testResult: json['test_result'] as String,
        status: json['status'] as String,
      );

  SterilizationCycle toDomain() => SterilizationCycle(
        id: id,
        autoclaveRef: autoclaveRef,
        cycleNumber: cycleNumber,
        startedAt: DateTime.parse(startedAt),
        testKind: testKind,
        testResult: testResult,
        status: status,
      );
}
