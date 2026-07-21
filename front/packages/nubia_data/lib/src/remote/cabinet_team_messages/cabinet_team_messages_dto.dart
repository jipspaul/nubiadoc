import 'package:nubia_domain/src/entities/cabinet_team_message.dart';

class CabinetTeamMessageDto {
  final String id;
  final String senderId;
  final String senderName;
  final String body;
  final String createdAt;

  const CabinetTeamMessageDto({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  factory CabinetTeamMessageDto.fromJson(Map<String, dynamic> json) =>
      CabinetTeamMessageDto(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        senderName: json['sender_name'] as String,
        body: json['body'] as String,
        createdAt: json['created_at'] as String,
      );

  CabinetTeamMessage toDomain() => CabinetTeamMessage(
        id: id,
        senderId: senderId,
        senderName: senderName,
        body: body,
        createdAt: DateTime.parse(createdAt),
      );
}
