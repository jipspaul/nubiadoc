import 'package:nubia_domain/src/entities/cabinet_team_message.dart';

/// Table de correspondance JSON ↔ [CabinetTeamMessageReferenceType] (#5131).
const _referenceTypeByWire = {
  'patient': CabinetTeamMessageReferenceType.patient,
  'devis': CabinetTeamMessageReferenceType.devis,
  'lab_work_order': CabinetTeamMessageReferenceType.labWorkOrder,
  'stock_request': CabinetTeamMessageReferenceType.stockRequest,
  'agenda_slot': CabinetTeamMessageReferenceType.agendaSlot,
};

class CabinetTeamMessageReferenceDto {
  final String type;
  final String targetId;
  final String title;
  final String subtitle;

  const CabinetTeamMessageReferenceDto({
    required this.type,
    required this.targetId,
    required this.title,
    required this.subtitle,
  });

  factory CabinetTeamMessageReferenceDto.fromJson(Map<String, dynamic> json) =>
      CabinetTeamMessageReferenceDto(
        type: json['type'] as String,
        targetId: json['target_id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String,
      );

  /// `null` si le type n'est pas reconnu (rétro-compatibilité : un backend
  /// plus récent peut introduire un type de référence inconnu du front).
  CabinetTeamMessageReference? toDomain() {
    final type = _referenceTypeByWire[this.type];
    if (type == null) return null;
    return CabinetTeamMessageReference(
      type: type,
      targetId: targetId,
      title: title,
      subtitle: subtitle,
    );
  }
}

class CabinetTeamMessageDto {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderRole;
  final String body;
  final String createdAt;
  final CabinetTeamMessageReferenceDto? reference;
  final bool pinned;
  final String? pinnedBy;
  final String? pinnedAt;
  final List<String> mentions;

  const CabinetTeamMessageDto({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderRole,
    required this.body,
    required this.createdAt,
    this.reference,
    this.pinned = false,
    this.pinnedBy,
    this.pinnedAt,
    this.mentions = const [],
  });

  factory CabinetTeamMessageDto.fromJson(Map<String, dynamic> json) =>
      CabinetTeamMessageDto(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        senderName: json['sender_name'] as String,
        senderRole: json['sender_role'] as String?,
        body: json['body'] as String,
        createdAt: json['created_at'] as String,
        reference: json['reference'] != null
            ? CabinetTeamMessageReferenceDto.fromJson(
                json['reference'] as Map<String, dynamic>)
            : null,
        pinned: json['pinned'] as bool? ?? false,
        pinnedBy: json['pinned_by'] as String?,
        pinnedAt: json['pinned_at'] as String?,
        mentions: (json['mentions'] as List<dynamic>?)
                ?.map((m) => m as String)
                .toList() ??
            const [],
      );

  CabinetTeamMessage toDomain() => CabinetTeamMessage(
        id: id,
        senderId: senderId,
        senderName: senderName,
        senderRole: senderRole,
        body: body,
        createdAt: DateTime.parse(createdAt),
        reference: reference?.toDomain(),
        pinned: pinned,
        pinnedBy: pinnedBy,
        pinnedAt: pinnedAt != null ? DateTime.parse(pinnedAt!) : null,
        mentions: mentions,
      );
}
