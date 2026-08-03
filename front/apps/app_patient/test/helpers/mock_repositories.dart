import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

// ── Patient-facing repositories ───────────────────────────────────────────────

class MockAccountRepository extends Mock implements AccountRepository {}

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBillingRepository extends Mock implements BillingRepository {}

class MockDashboardRepository extends Mock implements DashboardRepository {}

class MockDocumentRepository extends Mock implements DocumentRepository {}

class MockMessageRepository extends Mock implements MessageRepository {}

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

class MockReviewRepository extends Mock implements ReviewRepository {}

class MockSearchRepository extends Mock implements SearchRepository {}

class MockSignatureRepository extends Mock implements SignatureRepository {}

class MockSlotsRepository extends Mock implements SlotsRepository {}

// ── Pro-facing repositories ───────────────────────────────────────────────────

class MockCabinetAgendaRepository extends Mock
    implements CabinetAgendaRepository {}

class MockCabinetAppointmentsRepository extends Mock
    implements CabinetAppointmentsRepository {}

class MockCabinetPatientsRepository extends Mock
    implements CabinetPatientsRepository {}

class MockCabinetQuotesRepository extends Mock
    implements CabinetQuotesRepository {}

class MockClinicalSessionRepository extends Mock
    implements ClinicalSessionRepository {}

class MockMembersRepository extends Mock implements MembersRepository {}

class MockPrescriptionRepository extends Mock
    implements PrescriptionRepository {}

class MockSecretariatRepository extends Mock implements SecretariatRepository {}

class MockWaitingRoomRepository extends Mock implements WaitingRoomRepository {}

class MockWaitingListRepository extends Mock implements WaitingListRepository {}
