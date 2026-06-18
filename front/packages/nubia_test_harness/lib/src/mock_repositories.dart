import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

class MockAccountRepository extends Mock implements AccountRepository {}

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockDocumentRepository extends Mock implements DocumentRepository {}

class MockMessageRepository extends Mock implements MessageRepository {}
