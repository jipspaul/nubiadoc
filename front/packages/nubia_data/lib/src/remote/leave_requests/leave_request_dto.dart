import 'package:nubia_domain/src/entities/leave_request.dart';

class LeaveRequestDto {
  final String id;
  final String userId;
  final String startsAt;
  final String endsAt;
  final String kind;
  final String status;
  final String? decidedBy;

  const LeaveRequestDto({
    required this.id,
    required this.userId,
    required this.startsAt,
    required this.endsAt,
    required this.kind,
    required this.status,
    this.decidedBy,
  });

  factory LeaveRequestDto.fromJson(Map<String, dynamic> json) =>
      LeaveRequestDto(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        startsAt: json['starts_at'] as String,
        endsAt: json['ends_at'] as String,
        kind: json['kind'] as String,
        status: json['status'] as String,
        decidedBy: json['decided_by'] as String?,
      );

  LeaveRequest toDomain() => LeaveRequest(
        id: id,
        userId: userId,
        startsAt: startsAt,
        endsAt: endsAt,
        kind: kind,
        status: status,
        decidedBy: decidedBy,
      );
}
