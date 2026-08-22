import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/cabinet_appointments_dto.dart';
import 'package:nubia_domain/src/entities/cabinet_appointment.dart';
import 'package:nubia_data/src/remote/scheduling/appointment_dto.dart';
import 'package:nubia_data/src/remote/auth/auth_dto.dart';
import 'package:nubia_data/src/remote/account/account_dto.dart';
import 'package:nubia_data/src/remote/dashboard/dashboard_dto.dart';
import 'package:nubia_data/src/remote/payments_api.dart';
import 'package:nubia_data/src/remote/clinical/clinical_session_dto.dart';
import 'package:nubia_data/src/remote/search/search_dto.dart';
import 'package:nubia_data/src/remote/notifications/notification_dto.dart';
import 'package:nubia_data/src/remote/messaging/messaging_dto.dart';
import 'package:nubia_data/src/remote/documents/document_dto.dart';
import 'package:nubia_data/src/remote/billing/billing_dto.dart';

void main() {
  group('AppointmentDto (POST /v1/appointments/:id/cancel response)', () {
    test('fromJson désérialise un RDV annulé', () {
      final json = {
        'id': 'appt-1',
        'cabinet_id': 'cab-1',
        // #3825 : forme réelle de l'API — la spécialité est imbriquée sous
        // `provider`, jamais en `practitioner_specialty` de premier niveau
        // (cette clé n'existe dans AUCUNE réponse réelle du back).
        'provider': {'display_name': 'Dr Martin', 'specialty': 'Dentiste'},
        'starts_at': '2026-07-01T09:00:00Z',
        'duration_minutes': 30,
        'motif': 'Détartrage',
        'status': 'cancelled',
        'type': 'in_person',
      };
      final dto = AppointmentDto.fromJson(json);
      expect(dto.id, 'appt-1');
      expect(dto.status, 'cancelled');
      expect(dto.practitionerName, 'Dr Martin');
      expect(dto.practitionerSpecialty, 'Dentiste');
    });

    // #5563/#5593 : le champ imbriqué `beneficiary` (contrat réel de
    // GET/POST /v1/appointments) n'était jamais lu — un tuteur ne pouvait
    // donc jamais distinguer un RDV pris pour lui-même d'un RDV pris pour
    // un dépendant nommé.
    test('fromJson lit beneficiary.is_self=false + nom (RDV d\'un dépendant)',
        () {
      final dto = AppointmentDto.fromJson({
        'id': 'appt-2',
        'cabinet_id': 'cab-1',
        'provider': {'display_name': 'Dr Martin', 'specialty': 'Dentiste'},
        'starts_at': '2026-07-01T09:00:00Z',
        'duration_minutes': 30,
        'motif': 'QA dependent booking',
        'status': 'confirmed',
        'type': 'in_person',
        'beneficiary': {
          'account_id': '3e6db67e-e45c-4515-9988-8ef95f9ed138',
          'is_self': false,
          'first_name': 'QAFlow',
          'last_name': 'Dep',
        },
      });
      expect(dto.beneficiaryIsSelf, isFalse);
      expect(dto.beneficiaryName, 'QAFlow Dep');
      expect(dto.toDomain().beneficiaryIsSelf, isFalse);
      expect(dto.toDomain().beneficiaryName, 'QAFlow Dep');
    });

    test('fromJson lit beneficiary.is_self=true (RDV du tuteur lui-même)',
        () {
      final dto = AppointmentDto.fromJson({
        'id': 'appt-3',
        'cabinet_id': 'cab-1',
        'provider': {'display_name': 'Dr Martin', 'specialty': 'Dentiste'},
        'starts_at': '2026-07-01T09:00:00Z',
        'duration_minutes': 30,
        'motif': 'Consultation',
        'status': 'confirmed',
        'type': 'in_person',
        'beneficiary': {
          'account_id': 'a1111111-1111-1111-1111-111111111111',
          'is_self': true,
          'first_name': null,
          'last_name': null,
        },
      });
      expect(dto.beneficiaryIsSelf, isTrue);
      expect(dto.beneficiaryName, isNull);
    });

    test('fromJson : beneficiary absent -> repli sur is_self=true (rétrocompat)',
        () {
      final dto = AppointmentDto.fromJson({
        'id': 'appt-4',
        'cabinet_id': 'cab-1',
        'provider': {'display_name': 'Dr Martin', 'specialty': 'Dentiste'},
        'starts_at': '2026-07-01T09:00:00Z',
        'duration_minutes': 30,
        'motif': 'Consultation',
        'status': 'confirmed',
        'type': 'in_person',
      });
      expect(dto.beneficiaryIsSelf, isTrue);
      expect(dto.beneficiaryName, isNull);
    });

    // #5272 : montant des frais de non-présentation — lu depuis l'API,
    // jamais codé en dur.
    test('fromJson lit no_show_fee_cents quand présent', () {
      final dto = AppointmentDto.fromJson({
        'id': 'appt-5',
        'cabinet_id': 'cab-1',
        'provider': {'display_name': 'Dr Martin', 'specialty': 'Dentiste'},
        'starts_at': '2026-07-01T09:00:00Z',
        'duration_minutes': 30,
        'motif': 'Détartrage',
        'status': 'no_show',
        'type': 'in_person',
        'no_show_fee_cents': 3000,
      });
      expect(dto.noShowFeeCents, 3000);
      expect(dto.toDomain().noShowFeeCents, 3000);
    });

    test('fromJson : no_show_fee_cents absent -> null', () {
      final dto = AppointmentDto.fromJson({
        'id': 'appt-6',
        'cabinet_id': 'cab-1',
        'provider': {'display_name': 'Dr Martin', 'specialty': 'Dentiste'},
        'starts_at': '2026-07-01T09:00:00Z',
        'duration_minutes': 30,
        'motif': 'Détartrage',
        'status': 'no_show',
        'type': 'in_person',
      });
      expect(dto.noShowFeeCents, isNull);
      expect(dto.toDomain().noShowFeeCents, isNull);
    });

    // #5270 : montant de la facture d'un RDV terminé — lu depuis l'API,
    // jamais codé en dur.
    test('fromJson lit invoice_amount_cents quand présent', () {
      final dto = AppointmentDto.fromJson({
        'id': 'appt-7',
        'cabinet_id': 'cab-1',
        'provider': {'display_name': 'Dr Martin', 'specialty': 'Dentiste'},
        'starts_at': '2026-07-01T09:00:00Z',
        'duration_minutes': 30,
        'motif': 'Traitement de carie',
        'status': 'completed',
        'type': 'in_person',
        'invoice_amount_cents': 14850,
      });
      expect(dto.invoiceAmountCents, 14850);
      expect(dto.toDomain().invoiceAmountCents, 14850);
    });

    test('fromJson : invoice_amount_cents absent -> null', () {
      final dto = AppointmentDto.fromJson({
        'id': 'appt-8',
        'cabinet_id': 'cab-1',
        'provider': {'display_name': 'Dr Martin', 'specialty': 'Dentiste'},
        'starts_at': '2026-07-01T09:00:00Z',
        'duration_minutes': 30,
        'motif': 'Traitement de carie',
        'status': 'completed',
        'type': 'in_person',
      });
      expect(dto.invoiceAmountCents, isNull);
      expect(dto.toDomain().invoiceAmountCents, isNull);
    });
  });

  group('PatientAccountDto', () {
    test('fromJson désérialise un profil patient complet (forme account)', () {
      final json = {
        'id': 'user-42',
        'first_name': 'Camille',
        'last_name': 'Dupont',
        'email': 'camille@example.com',
        'phone': '+33612345678',
        'date_of_birth': '1990-05-15',
      };
      final dto = PatientAccountDto.fromJson(json);
      expect(dto.id, 'user-42');
      expect(dto.email, 'camille@example.com');
      expect(dto.phone, '+33612345678');
    });

    // Non-régression #3100/#3022 : le vrai contrat de GET /v1/me est
    // MeResponse {user_id, email, kind, account_id, memberships} — l'ancien
    // parsing attendait {id, first_name, …} et jetait, faisant retomber
    // AuthCubit.restore() en Unauthenticated après signup.
    test('fromMeJson désérialise le contrat réel de GET /v1/me (patient)', () {
      final json = {
        'user_id': 'b3b0c8e2-0000-0000-0000-000000000001',
        'email': 'camille@example.com',
        'kind': 'patient',
        'account_id': 'a1a0c8e2-0000-0000-0000-000000000002',
        'memberships': <dynamic>[],
      };
      final dto = PatientAccountDto.fromMeJson(json);
      expect(dto.id, 'a1a0c8e2-0000-0000-0000-000000000002');
      expect(dto.email, 'camille@example.com');
    });

    test('fromMeJson retombe sur user_id quand account_id est null (pro)', () {
      final json = {
        'user_id': 'b3b0c8e2-0000-0000-0000-000000000001',
        'email': 'pro@example.com',
        'kind': 'pro',
        'account_id': null,
        'memberships': <dynamic>[],
      };
      final dto = PatientAccountDto.fromMeJson(json);
      expect(dto.id, 'b3b0c8e2-0000-0000-0000-000000000001');
    });
  });

  group('AccountDto (GET /v1/account response)', () {
    test('fromJson désérialise les coordonnées du compte patient', () {
      final json = {
        'id': 'acc-7',
        'first_name': 'Alex',
        'last_name': 'Moreau',
        'email': 'alex@example.com',
        'phone': null,
        'date_of_birth': null,
      };
      final dto = AccountDto.fromJson(json);
      expect(dto.id, 'acc-7');
      expect(dto.firstName, 'Alex');
      expect(dto.phone, isNull);
    });
  });

  group('ReferringDoctorDto (GET/PUT /v1/account/referring-doctor)', () {
    // Régression #3843 : l'API ne renvoie JAMAIS name/phone/address — un
    // médecin hors annuaire est renvoyé sous free_name/free_phone/
    // free_address. `json['name'] as String` (cast non-nullable) levait un
    // TypeError sur ce contrat réel ⇒ écran cassé « Erreur de décodage »
    // alors que la requête répondait 200 avec des données valides.
    test('fromJson décode la forme free_* (médecin hors annuaire)', () {
      final dto = ReferringDoctorDto.fromJson({
        'free_name': 'Dr Hors Base',
        'free_phone': '0102030405',
        'free_address': '1 rue X',
      });
      expect(dto.name, 'Dr Hors Base');
      expect(dto.phone, '0102030405');
      expect(dto.address, '1 rue X');
      expect(dto.providerId, isNull);
    });

    test('fromJson préfère name/phone/address si présents (rétrocompat)', () {
      final dto = ReferringDoctorDto.fromJson({
        'name': 'Dr Annuaire',
        'phone': '0600000000',
        'free_name': 'Ignoré',
      });
      expect(dto.name, 'Dr Annuaire');
      expect(dto.phone, '0600000000');
    });
  });

  group('QuoteSignedDto (POST /v1/quotes/:id/sign response)', () {
    test('fromJson désérialise le contrat réel (signature synchrone, stub)',
        () {
      final json = {
        'signed': true,
        'signed_at': '2026-07-13T12:21:48.9+00:00',
      };
      final dto = QuoteSignedDto.fromJson(json);
      expect(dto.signed, isTrue);
      expect(dto.signedAt, '2026-07-13T12:21:48.9+00:00');
    });
  });

  group('PaymentIntentDto (POST /v1/payments/intent response)', () {
    test('fromJson désérialise un PaymentIntent Stripe', () {
      final json = {
        'payment_id': 'pi-stripe-xyz',
        'client_secret': 'pi_xyz_secret_abc',
      };
      final dto = PaymentIntentDto.fromJson(json);
      expect(dto.paymentId, 'pi-stripe-xyz');
      expect(dto.clientSecret, 'pi_xyz_secret_abc');
    });
  });

  group('DashboardDto (GET /v1/dashboard)', () {
    test(
      'fromJson désérialise un patient avec données (next_appointment, to_sign, to_pay)',
      () {
        final json = {
          'next_appointment': {
            'appointment_id': 'appt-abc',
            'starts_at': '2026-08-01T10:00:00Z',
            'status': 'confirmed',
          },
          'to_sign': [
            {'quote_id': 'q-1', 'amount_cents': 12000},
            {'quote_id': 'q-2', 'amount_cents': 8000},
          ],
          'to_pay': [
            {'payment_id': 'pay-1', 'amount_cents': 5000},
          ],
          'unread_messages': 3,
          'reminders': 1,
        };
        final dto = DashboardDto.fromJson(json);
        expect(dto.upcomingAppointments, 1);
        expect(dto.documentsToSign, 2);
        expect(dto.pendingPaymentsCents, 5000);
        expect(dto.unreadMessages, 3);
        final domain = dto.toDomain();
        expect(domain.upcomingAppointments, 1);
        expect(domain.documentsToSign, 2);
        expect(domain.pendingPaymentsCents, 5000);
      },
    );

    test(
      'fromJson désérialise un patient sans données (null / listes vides)',
      () {
        final json = {
          'next_appointment': null,
          'to_sign': [],
          'to_pay': [],
          'unread_messages': 0,
          'reminders': 0,
        };
        final dto = DashboardDto.fromJson(json);
        expect(dto.upcomingAppointments, 0);
        expect(dto.documentsToSign, 0);
        expect(dto.pendingPaymentsCents, 0);
        expect(dto.unreadMessages, 0);
      },
    );
  });

  group('ProviderResultDto (GET /v1/search/providers → data[])', () {
    test('parse le contrat réel : provider_id, distance_m, geo', () {
      final json = {
        'provider_id': 'f0000000-0000-0000-0000-0000000000f1',
        'display_name': 'Dr Hugo Marin',
        'specialty': 'Chirurgie dentaire',
        'sector': '1',
        'distance_m': 2500.0,
        'next_slot_at': '2026-07-04T09:00:00Z',
        'rating_avg': 4.6,
        'geo': {'lat': 45.758, 'lng': 4.835},
        'is_listed': true,
      };
      final dto = ProviderResultDto.fromJson(json);
      final domain = dto.toDomain();
      expect(domain.id, 'f0000000-0000-0000-0000-0000000000f1');
      expect(domain.specialty, 'Chirurgie dentaire');
      expect(domain.distanceKm, closeTo(2.5, 1e-9));
      expect(domain.lat, closeTo(45.758, 1e-9));
      expect(domain.lng, closeTo(4.835, 1e-9));
      expect(domain.hasLocation, isTrue);
      expect(domain.ratingAvg, 4.6);
    });

    test(
      'specialty null → libellé de repli, pas de geo → hasLocation false',
      () {
        final dto = ProviderResultDto.fromJson({
          'provider_id': 'p1',
          'display_name': 'Cabinet X',
          'is_listed': true,
        });
        final domain = dto.toDomain();
        expect(domain.specialty, 'Praticien');
        expect(domain.hasLocation, isFalse);
      },
    );
  });

  group('ParsedSearchDto (POST /v1/search/parse)', () {
    test('parse query structurée + interpretation + source', () {
      final dto = ParsedSearchDto.fromJson({
        'query': {
          'q': 'dentiste',
          'specialty': 'Chirurgie dentaire',
          'place': 'Bastille',
          'near': 'Paris',
          'sector': '1',
          'available': true,
          'teleconsult': false,
        },
        'interpretation': 'Dentiste secteur 1 près de Bastille',
        'source': 'llm',
      });
      final domain = dto.toDomain();
      expect(domain.query.q, 'dentiste');
      expect(domain.query.specialty, 'Chirurgie dentaire');
      expect(domain.query.sector, '1');
      expect(domain.query.available, isTrue);
      expect(domain.query.teleconsult, isFalse);
      expect(domain.interpretation, 'Dentiste secteur 1 près de Bastille');
      expect(domain.source, 'llm');
    });

    test('champs absents → valeurs de repli (q vide, source keywords)', () {
      final dto = ParsedSearchDto.fromJson({'query': {}});
      final domain = dto.toDomain();
      expect(domain.query.q, '');
      expect(domain.query.specialty, isNull);
      expect(domain.interpretation, '');
      expect(domain.source, 'keywords');
    });
  });

  group('SlotDto.fromAvailabilityJson (GET /providers/:id/availability)', () {
    test('parse slot_id/starts_at/ends_at', () {
      final dto = SlotDto.fromAvailabilityJson({
        'slot_id': 's1',
        'starts_at': '2026-07-04T09:00:00Z',
        'ends_at': '2026-07-04T09:30:00Z',
        'motif': null,
      });
      final slot = dto.toDomain();
      expect(slot.id, 's1');
      expect(slot.isAvailable, isTrue);
    });
  });

  group('Contrats réels vérifiés sur env déployé (QA)', () {
    test('NotificationDto : kind→type, is_read→read, pas de body', () {
      final dto = NotificationDto.fromJson({
        'id': 'n1',
        'kind': 'rdv_rappel',
        'title': 'Rappel RDV',
        'is_read': false,
        'created_at': '2026-06-02T18:00:00Z',
      });
      final d = dto.toDomain();
      expect(d.title, 'Rappel RDV');
      expect(d.read, isFalse);
      expect(d.body, '');
    });

    test(
      'MessageDto : body→text, created_at→sentAt, conversationId injecté',
      () {
        final dto = MessageDto.fromJson({
          'id': 'm1',
          'body': 'Bonjour',
          'sender': 'patient',
          'created_at': '2026-07-02T09:45:54Z',
          'read_at': null,
        }, conversationId: 'c1');
        final m = dto.toDomain();
        expect(m.text, 'Bonjour');
        expect(m.conversationId, 'c1');
        expect(m.sender.toString(), contains('patient'));
      },
    );

    test('ConversationDto : liste résumé (cabinet_name, unread_count)', () {
      final dto = ConversationDto.fromJson({
        'id': 'c1',
        'cabinet_id': 'cab',
        'cabinet_name': 'Cabinet Lyon',
        'last_message_at': '2026-07-02T09:45:54Z',
        'unread_count': 0,
      });
      final c = dto.toDomain();
      expect(c.cabinetName, 'Cabinet Lyon');
      expect(c.unreadCount, 0);
      expect(c.lastMessage, isNull);
      // #3348 : le contrat liste renvoie `last_message_at` (pas d'aperçu
      // texte) — on doit le mapper pour afficher l'horodatage du fil.
      expect(c.lastMessageAt, DateTime.parse('2026-07-02T09:45:54Z'));
    });

    test(
      'ConversationDto : aperçu du dernier message (last_message_preview)',
      () {
        final c = ConversationDto.fromJson({
          'id': 'c1',
          'cabinet_id': 'cab',
          'cabinet_name': 'Cabinet Lyon',
          'last_message_at': '2026-07-02T09:45:54Z',
          'last_message_preview': 'Bonjour, vos résultats sont disponibles.',
          'unread_count': 3,
        }).toDomain();
        expect(
          c.lastMessagePreview,
          'Bonjour, vos résultats sont disponibles.',
        );
      },
    );

    test('ConversationDto : last_message_at absent → lastMessageAt null', () {
      final c = ConversationDto.fromJson({
        'id': 'c1',
        'cabinet_id': 'cab',
        'cabinet_name': 'Cabinet Lyon',
        'unread_count': 3,
      }).toDomain();
      expect(c.lastMessageAt, isNull);
      expect(c.unreadCount, 3);
    });

    test('DocumentDto : size_bytes (contrat réel) → fileSizeBytes', () {
      // #3349 : le champ réel est `size_bytes` (api/src/documents.rs).
      final d = DocumentDto.fromJson({
        'id': 'doc-1',
        'category': 'devis',
        'filename': 'Devis.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 204800,
        'created_at': '2026-07-02T09:45:54Z',
      }).toDomain();
      expect(d.fileSizeBytes, 204800);
    });

    test('DocumentDto : size_bytes absent (contrat liste) → 0', () {
      final d = DocumentDto.fromJson({
        'id': 'doc-1',
        'category': 'devis',
        'filename': 'Devis.pdf',
        'mime_type': 'application/pdf',
        'created_at': '2026-07-02T09:45:54Z',
      }).toDomain();
      expect(d.fileSizeBytes, 0);
    });

    test(
        'DocumentDto.fromUploadResponse : parse la réponse 201 sans id/mime_type/created_at (#3831)',
        () {
      // api/src/documents.rs UploadDocumentResponse : {document_id, category,
      // filename, size_bytes, sha256} — pas de id/mime_type/created_at.
      // DocumentDto.fromJson levait un TypeError sur ce payload (ParseFailure
      // générique → snackbar erreur sur un upload pourtant réussi, #3831).
      final d = DocumentDto.fromUploadResponse(
        {
          'document_id': '2cf0c976-0a9d-4cbf-b41a-0be5913b31d0',
          'category': 'facture',
          'filename': 'QA-verify-doc.pdf',
          'size_bytes': 44,
          'sha256': '5685efbc',
        },
        filename: 'QA-verify-doc.pdf',
        mimeType: 'application/pdf',
      );
      expect(d.id, '2cf0c976-0a9d-4cbf-b41a-0be5913b31d0');
      expect(d.category, 'facture');
      expect(d.filename, 'QA-verify-doc.pdf');
      expect(d.mimeType, 'application/pdf');
      expect(d.fileSizeBytes, 44);
      expect(d.sha256, '5685efbc');
      // toDomain() ne doit pas lever (createdAt dérivé, pas absent).
      expect(() => d.toDomain(), returnsNormally);
    });

    test('QuoteDto.fromSummaryJson : liste devis (total_amount_cents)', () {
      final q = QuoteDto.fromSummaryJson({
        'id': 'q1',
        'status': 'signed',
        'total_amount_cents': 38000,
        'currency': 'EUR',
        'created_at': '2026-07-03T06:15:29Z',
      }).toDomain();
      expect(q.totalCents, 38000);
      expect(q.status.toString(), contains('signed'));
      expect(q.items, isEmpty);
    });

    test(
      'QuoteDto.fromJson : détail avec items unit_amount_cents/amo_part',
      () {
        final q = QuoteDto.fromJson({
          'id': 'q1',
          'status': 'signed',
          'total_amount_cents': 38000,
          'created_at': '2026-07-03T06:15:29Z',
          'signed_at': '2026-07-03T06:15:29Z',
          'items': [
            {
              'id': 'i1',
              'label': 'Composite',
              'ccam_code': null,
              'tooth': null,
              'unit_amount_cents': 30000,
              'amo_part_cents': 10000,
              'amc_part_cents': 5000,
            },
          ],
        }).toDomain();
        expect(q.items, hasLength(1));
        expect(q.items.first.totalCents, 30000);
        expect(q.items.first.patientShareCents, 15000); // 30000-10000-5000
      },
    );
  });

  // --- Confirmation RDV cabinet (issue #3361) ---------------------------------
  group('CabinetAppointmentDto.fromConfirmResponse', () {
    test('parse la réponse 200 { appointment_id, status } sans erreur', () {
      final dto = CabinetAppointmentDto.fromConfirmResponse({
        'appointment_id': '488801b0-17d9-4ec7-8d52-c475f2564b34',
        'status': 'confirmed',
      });
      expect(dto.id, '488801b0-17d9-4ec7-8d52-c475f2564b34');
      expect(dto.status, 'confirmed');
      // toDomain() ne doit pas lever (starts_at valide, statut mappé).
      final domain = dto.toDomain();
      expect(domain.id, '488801b0-17d9-4ec7-8d52-c475f2564b34');
      expect(domain.status, CabinetAppointmentStatus.confirmed);
    });
  });

  // #4608 : GET /cabinet/appointments émet `practitioner_name` (fix API) —
  // le DTO doit le lire, sinon la ligne RDV secrétariat affiche « · <date> »
  // avec un séparateur pendant faute de nom de praticien.
  group('CabinetAppointmentDto (GET /cabinet/appointments)', () {
    test('fromJson lit practitioner_name (clé réellement émise par l\'API)', () {
      final dto = CabinetAppointmentDto.fromJson({
        'id': 'appt-1',
        'practitioner_id': 'prac-1',
        'patient_id': 'pat-1',
        'patient_name': 'Jean Dupont',
        'practitioner_name': 'Dr Hugo Marin',
        'starts_at': '2026-01-06T09:00:00Z',
        'ends_at': '2026-01-06T09:30:00Z',
        'status': 'confirmed',
      });
      expect(dto.practitionerName, 'Dr Hugo Marin');
    });

    test('fromJson retombe sur \'\' quand practitioner_name est absent (pas de crash)', () {
      final dto = CabinetAppointmentDto.fromJson({
        'id': 'appt-1',
        'practitioner_id': 'prac-1',
        'patient_id': 'pat-1',
        'starts_at': '2026-01-06T09:00:00Z',
        'ends_at': '2026-01-06T09:30:00Z',
        'status': 'confirmed',
      });
      expect(dto.practitionerName, '');
    });
  });

  group('ClinicalSessionDto (POST /v1/cabinet/appointments/:id/start)', () {
    test('fromJson accepte `consultation_id` (réponse du start)', () {
      // Le back renvoie `consultation_id`, pas `id`.
      final dto = ClinicalSessionDto.fromJson({
        'appointment_id': 'aa-1',
        'consultation_id': 'cs-1',
        'status': 'in_progress',
        'started_at': '2026-07-04T19:31:58Z',
      });
      expect(dto.id, 'cs-1');
      expect(dto.appointmentId, 'aa-1');
      expect(dto.acts, isEmpty);
      expect(dto.toDomain().id, 'cs-1');
    });

    test('fromJson accepte `id` (réponse du GET consultation)', () {
      final dto = ClinicalSessionDto.fromJson({
        'id': 'cs-2',
        'appointment_id': 'aa-2',
        'status': 'in_progress',
        'acts': [],
      });
      expect(dto.id, 'cs-2');
    });

    test('fromJson remonte patient_name et started_at de la liste (#3371)', () {
      final session = ClinicalSessionDto.fromJson({
        'id': 'cs-3',
        'appointment_id': 'aa-3',
        'patient_name': 'Marc Dubois',
        'status': 'in_progress',
        'started_at': '2026-07-06T09:30:00Z',
        'acts': [],
      }).toDomain();
      expect(session.patientName, 'Marc Dubois');
      expect(session.startedAt, DateTime.utc(2026, 7, 6, 9, 30));
    });

    test('fromJson remonte medical_alerts du détail (#4936)', () {
      final session = ClinicalSessionDto.fromJson({
        'id': 'cs-4',
        'appointment_id': 'aa-4',
        'status': 'in_progress',
        'acts': [],
        'medical_alerts': [
          {'kind': 'allergie', 'label': 'Pénicilline'},
          {'kind': 'medico_legal', 'label': 'Anticoagulant (AVK)'},
        ],
      }).toDomain();
      expect(session.medicalAlerts, hasLength(2));
      expect(session.medicalAlerts.first.kind, 'allergie');
      expect(session.medicalAlerts.first.label, 'Pénicilline');
      expect(session.medicalAlerts.last.kind, 'medico_legal');
    });

    test('fromJson sans medical_alerts → liste vide (route start/liste)', () {
      final session = ClinicalSessionDto.fromJson({
        'appointment_id': 'aa-5',
        'consultation_id': 'cs-5',
        'status': 'in_progress',
      }).toDomain();
      expect(session.medicalAlerts, isEmpty);
    });

    test('fromJson remonte patient_birth_date du détail (#4945)', () {
      final session = ClinicalSessionDto.fromJson({
        'id': 'cs-6',
        'appointment_id': 'aa-6',
        'status': 'in_progress',
        'acts': [],
        'patient_name': 'Camille Moreau',
        'patient_birth_date': '1992-03-12',
      }).toDomain();
      final birthDate = session.patientBirthDate;
      expect(birthDate, isNotNull);
      expect(birthDate!.year, 1992);
      expect(birthDate.month, 3);
      expect(birthDate.day, 12);
    });

    test('fromJson sans patient_birth_date → null (route start/liste)', () {
      final session = ClinicalSessionDto.fromJson({
        'appointment_id': 'aa-7',
        'consultation_id': 'cs-7',
        'status': 'in_progress',
      }).toDomain();
      expect(session.patientBirthDate, isNull);
    });

    test('fromJson remonte last_visit_at du détail (#4956)', () {
      final session = ClinicalSessionDto.fromJson({
        'id': 'cs-8',
        'appointment_id': 'aa-8',
        'status': 'in_progress',
        'acts': [],
        'patient_name': 'Camille Moreau',
        'last_visit_at': '2026-07-22',
      }).toDomain();
      final lastVisitDate = session.lastVisitDate;
      expect(lastVisitDate, isNotNull);
      expect(lastVisitDate!.year, 2026);
      expect(lastVisitDate.month, 7);
      expect(lastVisitDate.day, 22);
    });

    test('fromJson sans last_visit_at → null (segment masqué)', () {
      final session = ClinicalSessionDto.fromJson({
        'appointment_id': 'aa-9',
        'consultation_id': 'cs-9',
        'status': 'in_progress',
      }).toDomain();
      expect(session.lastVisitDate, isNull);
    });

    test('fromJson remonte patient_id et active_plan du détail (#4938)', () {
      final session = ClinicalSessionDto.fromJson({
        'id': 'cs-6',
        'appointment_id': 'aa-6',
        'patient_id': 'pat-6',
        'status': 'in_progress',
        'acts': [],
        'active_plan': {
          'id': 'plan-1',
          'title': 'Réhabilitation secteur 2',
          'current_phase': 2,
          'total_phases': 3,
          'total_cost_cents': 163592,
        },
      }).toDomain();
      expect(session.patientId, 'pat-6');
      expect(session.activePlan?.id, 'plan-1');
      expect(session.activePlan?.title, 'Réhabilitation secteur 2');
      expect(session.activePlan?.currentPhase, 2);
      expect(session.activePlan?.totalPhases, 3);
      expect(session.activePlan?.totalCostCents, 163592);
    });

    test('fromJson sans active_plan → null (aucun plan inventé)', () {
      final session = ClinicalSessionDto.fromJson({
        'id': 'cs-7',
        'appointment_id': 'aa-7',
        'status': 'in_progress',
        'acts': [],
      }).toDomain();
      expect(session.activePlan, isNull);
      expect(session.patientId, isNull);
    });
  });
}
