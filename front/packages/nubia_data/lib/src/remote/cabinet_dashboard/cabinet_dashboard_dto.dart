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
        todayAppointments: (json['today_appointments'] as num).toInt(),
        waitingRoomCount: (json['waiting_room_count'] as num).toInt(),
        unreadMessages: (json['unread_messages'] as num).toInt(),
        pendingConfirmations: (json['pending_confirmations'] as num).toInt(),
      );

  ProDashboardSummary toDomain() => ProDashboardSummary(
        todayAppointments: todayAppointments,
        waitingRoomCount: waitingRoomCount,
        unreadMessages: unreadMessages,
        pendingConfirmations: pendingConfirmations,
      );
}
