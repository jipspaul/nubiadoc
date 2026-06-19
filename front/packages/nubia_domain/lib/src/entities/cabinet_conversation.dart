import 'package:equatable/equatable.dart';
import 'message.dart';

class CabinetConversation extends Equatable {
  final String id;
  final String patientId;
  final String patientName;
  final int unreadCount;
  final Message? lastMessage;

  const CabinetConversation({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.unreadCount,
    this.lastMessage,
  });

  @override
  List<Object?> get props => [id];
}
