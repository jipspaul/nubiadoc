import 'package:nubia_domain/nubia_domain.dart';

class CabinetDashboardDto {
  final int todayAppointments;
  final int waitingRoomCount;
  final int unreadMessages;
  final int pendingConfirmations;

  const CabinetDashboardDto({
    required this.todayAppointments,
    required this.waitingRoomCount,
    required this.unreadMessages,
    required this.pendingConfirmations,
  });

  factory CabinetDashboardDto.fromJson(Map<String, dynamic> json) =>
      CabinetDashboardDto(
        todayAppointments: (json['today_appointments'] as num?)?.toInt() ?? 0,
        waitingRoomCount: (json['waiting_room_count'] as num?)?.toInt() ?? 0,
        unreadMessages: (json['unread_messages'] as num?)?.toInt() ?? 0,
        pendingConfirmations:
            (json['pending_confirmations'] as num?)?.toInt() ?? 0,
      );

  ProDashboardSummary toDomain() => ProDashboardSummary(
        todayAppointments: todayAppointments,
        waitingRoomCount: waitingRoomCount,
        unreadMessages: unreadMessages,
        pendingConfirmations: pendingConfirmations,
      );
}
