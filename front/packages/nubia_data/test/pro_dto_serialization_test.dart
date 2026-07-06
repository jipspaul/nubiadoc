import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/src/remote/cabinet_dashboard/cabinet_dashboard_dto.dart';
import 'package:nubia_data/src/remote/cabinet_messaging/cabinet_messaging_dto.dart';
import 'package:nubia_data/src/remote/cabinet_patients/cabinet_patients_dto.dart';
import 'package:nubia_data/src/remote/cabinet_agenda/cabinet_agenda_dto.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/cabinet_appointments_dto.dart';
import 'package:nubia_data/src/remote/consultation/consultation_dto.dart';
import 'package:nubia_data/src/remote/waiting_room/waiting_room_dto.dart';
import 'package:nubia_data/src/remote/search/search_dto.dart';
import 'package:nubia_data/src/remote/members/members_dto.dart';
import 'package:nubia_data/src/remote/secretariat/secretariat_dto.dart';
import 'package:nubia_data/src/remote/cabinet_quotes/cabinet_quotes_dto.dart';
import 'package:nubia_domain/src/entities/cabinet_appointment.dart';
import 'package:nubia_domain/src/entities/cabinet_quote.dart';
import 'package:nubia_domain/src/entities/member.dart';

void main() {
  group('CabinetPatientDto (GET /v1/cabinet/patients)', () {
    test(
        'fromJson désérialise la réponse réelle de l\'API (sans cabinet_id ni email)',
        () {
      final json = {
        'id': 'd0000000-0000-0000-0000-0000000000d5',
        'first_name': 'Karim',
        'last_name': 'Saïdi',
        'birth_date': '1985-01-30',
        'created_at': '2026-06-21T10:24:38.232439+00:00',
      };
      final dto = CabinetPatientDto.fromJson(json);
      expect(dto.id, 'd0000000-0000-0000-0000-0000000000d5');
      expect(dto.cabinetId, '');
      expect(dto.firstName, 'Karim');
      expect(dto.lastName, 'Saïdi');
      expect(dto.email, isNull);
      final domain = dto.toDomain();
      expect(domain.fullName, 'Karim Saïdi');
      expect(domain.birthDate, isNotNull);
      expect(domain.lastVisitAt, isNull);
    });

    test(
        'fromJson tolère cabinet_id et champs optionnels présents (rétrocompat)',
        () {
      final json = {
        'id': 'pat-1',
        'cabinet_id': 'cab-1',
        'first_name': 'Marie',
        'last_name': 'Dupont',
        'birth_date': '1985-03-12',
        'email': 'marie@example.com',
        'phone': '+33611223344',
        'social_security_number': null,
        'last_visit_at': '2026-05-01T10:00:00Z',
        'created_at': '2024-01-10T08:00:00Z',
      };
      final dto = CabinetPatientDto.fromJson(json);
      expect(dto.cabinetId, 'cab-1');
      expect(dto.email, 'marie@example.com');
      final domain = dto.toDomain();
      expect(domain.lastVisitAt, isNotNull);
    });
  });

  group('AgendaEntryDto (GET /v1/cabinet/agenda)', () {
    test('fromJson désérialise une entrée agenda libre', () {
      final json = {
        'id': 'agenda-1',
        'cabinet_id': 'cab-1',
        'practitioner_id': 'prac-1',
        'practitioner_name': 'Dr Martin',
        'starts_at': '2026-07-01T09:00:00Z',
        'ends_at': '2026-07-01T09:30:00Z',
        'patient_id': null,
        'patient_name': null,
        'motif': null,
        'is_free': true,
      };
      final dto = AgendaEntryDto.fromJson(json);
      expect(dto.id, 'agenda-1');
      expect(dto.isFree, isTrue);
      expect(dto.patientId, isNull);
      final domain = dto.toDomain();
      expect(domain.duration.inMinutes, 30);
    });
  });

  group('CabinetAppointmentDto (GET /v1/cabinet/appointments)', () {
    test('fromJson désérialise un RDV cabinet confirmé', () {
      final json = {
        'id': 'rdv-1',
        'cabinet_id': 'cab-1',
        'patient_id': 'pat-1',
        'patient_name': 'Marie Dupont',
        'practitioner_id': 'prac-1',
        'practitioner_name': 'Dr Martin',
        'starts_at': '2026-07-10T14:00:00Z',
        'duration_minutes': 45,
        'motif': 'Détartrage',
        'status': 'confirmed',
      };
      final dto = CabinetAppointmentDto.fromJson(json);
      expect(dto.id, 'rdv-1');
      expect(dto.status, 'confirmed');
      final domain = dto.toDomain();
      expect(domain.status, CabinetAppointmentStatus.confirmed);
      expect(domain.duration.inMinutes, 45);
      expect(domain.isConfirmed, isTrue);
    });
  });

  group('ConsultationContextDto (GET /v1/cabinet/consultations/:id)', () {
    test('fromJson désérialise une consultation en cours', () {
      final json = {
        'id': 'consult-1',
        'cabinet_id': 'cab-1',
        'appointment_id': 'rdv-1',
        'patient_id': 'pat-1',
        'patient_name': 'Marie Dupont',
        'practitioner_id': 'prac-1',
        'started_at': '2026-07-10T14:05:00Z',
        'ended_at': null,
        'notes': null,
        'is_completed': false,
      };
      final dto = ConsultationContextDto.fromJson(json);
      expect(dto.id, 'consult-1');
      expect(dto.isCompleted, isFalse);
      expect(dto.endedAt, isNull);
      final domain = dto.toDomain();
      expect(domain.isCompleted, isFalse);
      expect(domain.endedAt, isNull);
    });
  });

  group('WaitingRoomEntryDto (GET /v1/cabinet/waiting-room)', () {
    test('fromJson désérialise une entrée salle d\'attente', () {
      final json = {
        'id': 'wr-1',
        'cabinet_id': 'cab-1',
        'patient_id': 'pat-1',
        'patient_name': 'Marie Dupont',
        'appointment_id': 'rdv-1',
        'arrived_at': '2026-07-10T13:55:00Z',
        'estimated_wait_minutes': 10,
      };
      final dto = WaitingRoomEntryDto.fromJson(json);
      expect(dto.id, 'wr-1');
      expect(dto.estimatedWaitMinutes, 10);
      final domain = dto.toDomain();
      expect(domain.appointmentId, 'rdv-1');
    });
  });

  group('WaitingListEntryDto (GET /v1/cabinet/waiting-list)', () {
    test('fromJson désérialise une entrée liste d\'attente', () {
      final json = {
        'id': 'wl-1',
        'cabinet_id': 'cab-1',
        'patient_id': 'pat-2',
        'patient_name': 'Jean Martin',
        'motif': 'Urgence',
        'requested_at': '2026-07-09T16:00:00Z',
        'position': 3,
      };
      final dto = WaitingListEntryDto.fromJson(json);
      expect(dto.id, 'wl-1');
      expect(dto.position, 3);
      final domain = dto.toDomain();
      expect(domain.motif, 'Urgence');
    });
  });

  group('SlotDto (GET /v1/cabinet/slots)', () {
    test('fromJson désérialise un créneau disponible', () {
      final json = {
        'id': 'slot-1',
        'cabinet_id': 'cab-1',
        'practitioner_id': 'prac-1',
        'starts_at': '2026-07-15T10:00:00Z',
        'ends_at': '2026-07-15T10:30:00Z',
        'is_available': true,
      };
      final dto = SlotDto.fromJson(json);
      expect(dto.id, 'slot-1');
      expect(dto.isAvailable, isTrue);
      final domain = dto.toDomain();
      expect(domain.duration.inMinutes, 30);
    });
  });

  group('MemberDto (GET /v1/cabinet/members)', () {
    test('fromJson désérialise la réponse réelle de l\'API (user_id, active)',
        () {
      final json = {
        'user_id': 'mem-1',
        'first_name': 'Luc',
        'last_name': 'Bernard',
        'email': 'luc@cabinet.fr',
        'role': 'practitioner',
        'active': true,
        'joined_at': '2023-09-01T00:00:00Z',
      };
      final dto = MemberDto.fromJson(json);
      expect(dto.id, 'mem-1');
      expect(dto.role, 'practitioner');
      expect(dto.isActive, isTrue);
      final domain = dto.toDomain();
      expect(domain.role, MemberRole.practitioner);
      expect(domain.fullName, 'Luc Bernard');
    });

    test('fromJson tolère first_name/last_name null', () {
      final json = {
        'user_id': 'mem-2',
        'first_name': null,
        'last_name': null,
        'email': 'invite@cabinet.fr',
        'role': 'secretary',
        'active': false,
        'joined_at': '2024-01-01T00:00:00Z',
      };
      final dto = MemberDto.fromJson(json);
      expect(dto.firstName, '');
      expect(dto.lastName, '');
      expect(dto.isActive, isFalse);
    });
  });

  group('SecretariatDto (GET /v1/cabinet/secretariats)', () {
    test(
        'fromJson désérialise la réponse réelle de l\'API (id, name, created_at)',
        () {
      final json = {
        'id': 'sec-1',
        'name': 'Secrétariat A',
        'created_at': '2023-01-01T00:00:00Z',
      };
      final dto = SecretariatDto.fromJson(json);
      expect(dto.id, 'sec-1');
      expect(dto.name, 'Secrétariat A');
      expect(dto.cabinetId, '');
      expect(dto.email, '');
      final domain = dto.toDomain();
      expect(domain.isActive, isTrue);
      expect(domain.phone, isNull);
    });
  });

  group('CabinetQuoteDto (GET /v1/cabinet/quotes)', () {
    test(
        'fromJson désérialise la réponse réelle de l\'API (total_amount, sans cabinet_id ni patient_share_cents)',
        () {
      final json = {
        'id': 'a1000000-0000-0000-0000-000000000003',
        'patient_id': 'd0000000-0000-0000-0000-0000000000d5',
        'patient_name': 'Karim Saïdi',
        'status': 'signed',
        'total_amount': 80000,
        'created_at': '2026-06-21T10:24:38.232439+00:00',
      };
      final dto = CabinetQuoteDto.fromJson(json);
      expect(dto.id, 'a1000000-0000-0000-0000-000000000003');
      expect(dto.totalCents, 80000);
      expect(dto.cabinetId, '');
      expect(dto.patientShareCents, 0);
      expect(dto.status, 'signed');
      final domain = dto.toDomain();
      expect(domain.status, CabinetQuoteStatus.signed);
      expect(domain.isSigned, isTrue);
      expect(domain.signedAt, isNull);
    });

    test('fromJson tolère total_cents (rétrocompat) et cabinet_id présent', () {
      final json = {
        'id': 'q-1',
        'cabinet_id': 'cab-1',
        'patient_id': 'pat-1',
        'patient_name': 'Marie Dupont',
        'total_cents': 85000,
        'patient_share_cents': 25000,
        'status': 'draft',
        'created_at': '2026-06-01T12:00:00Z',
        'signed_at': null,
        'expires_at': null,
      };
      final dto = CabinetQuoteDto.fromJson(json);
      expect(dto.totalCents, 85000);
      expect(dto.cabinetId, 'cab-1');
      expect(dto.patientShareCents, 25000);
    });
  });

  group('CabinetConversationDto (GET /v1/cabinet/conversations)', () {
    test(
        'fromJson désérialise la forme réelle de l\'API (patient_first/last_name)',
        () {
      final json = {
        'id': 'c1000000-0000-0000-0000-000000000002',
        'patient_first_name': 'Marc',
        'patient_last_name': 'Dubois',
        'last_message_at': '2026-06-03T08:00:00+00:00',
        'triage_flag': 'urgent',
        'unread_count': 1,
        'scope': 'patient_cabinet',
        'status': 'open',
      };
      final dto = CabinetConversationDto.fromJson(json);
      expect(dto.id, 'c1000000-0000-0000-0000-000000000002');
      expect(dto.patientName, 'Marc Dubois');
      expect(dto.patientId, '');
      expect(dto.unreadCount, 1);
      expect(dto.lastMessageAt, '2026-06-03T08:00:00+00:00');
      expect(dto.lastMessage, isNull);
      final domain = dto.toDomain();
      expect(domain.patientName, 'Marc Dubois');
      expect(domain.unreadCount, 1);
      expect(domain.lastMessageAt, isNotNull);
    });

    test('fromJson lit last_message_preview (#3373)', () {
      final dto = CabinetConversationDto.fromJson({
        'id': 'c1',
        'patient_first_name': 'Marc',
        'patient_last_name': 'Dubois',
        'last_message_at': '2026-06-03T08:00:00+00:00',
        'last_message_preview': 'Bonjour docteur, j\'ai une question.',
        'triage_flag': 'normal',
        'unread_count': 2,
        'scope': 'patient_cabinet',
        'status': 'open',
      });
      expect(
        dto.toDomain().lastMessagePreview,
        'Bonjour docteur, j\'ai une question.',
      );
    });

    test(
        'fromJson accepte patient_name direct (champ absent dans l\'API réelle)',
        () {
      final json = {
        'id': 'conv-2',
        'patient_id': 'pat-2',
        'patient_name': 'Camille Rousseau',
        'unread_count': 0,
      };
      final dto = CabinetConversationDto.fromJson(json);
      expect(dto.patientName, 'Camille Rousseau');
      expect(dto.patientId, 'pat-2');
      expect(dto.unreadCount, 0);
    });
  });

  group('CabinetDashboardDto (agrégation /v1/cabinet/dashboard)', () {
    test('fromJson désérialise les 4 compteurs présents', () {
      final json = {
        'today_appointments': 3,
        'waiting_room_count': 1,
        'unread_messages': 2,
        'pending_confirmations': 0,
      };
      final dto = CabinetDashboardDto.fromJson(json);
      expect(dto.todayAppointments, 3);
      expect(dto.waitingRoomCount, 1);
      expect(dto.unreadMessages, 2);
      expect(dto.pendingConfirmations, 0);
      final domain = dto.toDomain();
      expect(domain.todayAppointments, 3);
      expect(domain.waitingRoomCount, 1);
      expect(domain.unreadMessages, 2);
      expect(domain.pendingConfirmations, 0);
    });

    test('fromJson retourne 0 pour les champs manquants ou nuls', () {
      final dto = CabinetDashboardDto.fromJson({});
      expect(dto.todayAppointments, 0);
      expect(dto.waitingRoomCount, 0);
      expect(dto.unreadMessages, 0);
      expect(dto.pendingConfirmations, 0);
    });
  });
}
