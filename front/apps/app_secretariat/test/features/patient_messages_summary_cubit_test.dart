import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/dashboard/patient_messages_summary_cubit.dart';

class _MockListConversations extends Mock
    implements ListCabinetConversationsUseCase {}

CabinetConversation _conversation(
  String id, {
  required int unreadCount,
  String patientName = 'Patient',
  MessageUrgency triageFlag = MessageUrgency.normal,
}) =>
    CabinetConversation(
      id: id,
      patientId: 'p-$id',
      patientName: patientName,
      unreadCount: unreadCount,
      triageFlag: triageFlag,
    );

void main() {
  group('PatientMessagesSummaryCubit', () {
    late _MockListConversations listConversations;

    setUp(() {
      listConversations = _MockListConversations();
    });

    blocTest<PatientMessagesSummaryCubit, PatientMessagesSummaryState>(
      '#5379 : cumule le non-lu et met en avant le message urgent',
      build: () {
        when(() => listConversations()).thenAnswer(
          (_) async => Right([
            _conversation('c1', unreadCount: 2),
            _conversation(
              'c2',
              unreadCount: 1,
              patientName: 'Ahmed Belkacem',
              triageFlag: MessageUrgency.urgent,
            ),
            _conversation('c3', unreadCount: 1),
          ]),
        );
        return PatientMessagesSummaryCubit(
          listConversations: listConversations,
        );
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const PatientMessagesSummaryLoading(),
        const PatientMessagesSummaryLoaded(
          unreadCount: 4,
          urgentUnreadCount: 1,
          urgentPatientName: 'Ahmed Belkacem',
          urgentConversationId: 'c2',
        ),
      ],
    );

    blocTest<PatientMessagesSummaryCubit, PatientMessagesSummaryState>(
      'ignore un marquage urgent déjà lu (unreadCount = 0)',
      build: () {
        when(() => listConversations()).thenAnswer(
          (_) async => Right([
            _conversation(
              'c1',
              unreadCount: 0,
              patientName: 'Ahmed Belkacem',
              triageFlag: MessageUrgency.urgent,
            ),
          ]),
        );
        return PatientMessagesSummaryCubit(
          listConversations: listConversations,
        );
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const PatientMessagesSummaryLoading(),
        const PatientMessagesSummaryLoaded(
          unreadCount: 0,
          urgentUnreadCount: 0,
        ),
      ],
    );

    blocTest<PatientMessagesSummaryCubit, PatientMessagesSummaryState>(
      'aucune conversation → 0 message, pas d\'urgent',
      build: () {
        when(() => listConversations()).thenAnswer((_) async => const Right([]));
        return PatientMessagesSummaryCubit(
          listConversations: listConversations,
        );
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const PatientMessagesSummaryLoading(),
        const PatientMessagesSummaryLoaded(unreadCount: 0, urgentUnreadCount: 0),
      ],
    );

    blocTest<PatientMessagesSummaryCubit, PatientMessagesSummaryState>(
      'échec réseau → PatientMessagesSummaryError (pas un faux 0)',
      build: () {
        when(() => listConversations())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return PatientMessagesSummaryCubit(
          listConversations: listConversations,
        );
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const PatientMessagesSummaryLoading(),
        isA<PatientMessagesSummaryError>(),
      ],
    );
  });
}
