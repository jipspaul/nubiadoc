import 'package:equatable/equatable.dart';

/// Résultat de la conversion d'une conversation en RDV (#4159/#4160).
/// Source : `POST /v1/cabinet/conversations/{id}/convert-to-appointment`.
class ConversationAppointmentConversion extends Equatable {
  final String appointmentId;
  final String status;

  const ConversationAppointmentConversion({
    required this.appointmentId,
    required this.status,
  });

  @override
  List<Object?> get props => [appointmentId, status];
}
