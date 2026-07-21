import 'package:equatable/equatable.dart';

class CabinetTeamMessage extends Equatable {
  final String id;
  final String senderId;
  final String senderName;
  final String body;
  final DateTime createdAt;

  const CabinetTeamMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, senderId, senderName, body, createdAt];
}
