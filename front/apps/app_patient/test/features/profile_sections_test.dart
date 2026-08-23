import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/consents/consents_cubit.dart';
import 'package:app_patient/features/dependents/dependents_cubit.dart';
import 'package:app_patient/features/notification_prefs/notification_prefs_cubit.dart';

class _MockList extends Mock implements ListDependentsUseCase {}

class _MockListAccessRequests extends Mock
    implements ListAccessRequestsUseCase {}

class _MockGetUpcomingAppointments extends Mock
    implements GetUpcomingAppointmentsUseCase {}

class _MockAdd extends Mock implements AddDependentUseCase {}

class _MockDelete extends Mock implements DeleteDependentUseCase {}

class _MockResendAccessRequest extends Mock
    implements ResendAccessRequestUseCase {}

class _MockCancelAccessRequest extends Mock
    implements CancelAccessRequestUseCase {}

class _MockGetAccount extends Mock implements GetAccountUseCase {}

class _MockListConsents extends Mock implements ListConsentsUseCase {}

class _MockSetConsent extends Mock implements SetConsentUseCase {}

class _MockListPatientPharmacyOrders extends Mock
    implements ListPatientPharmacyOrdersUseCase {}

class _MockGetMyPharmacy extends Mock implements GetMyPharmacyUseCase {}

class _MockGetPrefs extends Mock implements GetNotificationPreferencesUseCase {}

class _MockUpdatePrefs extends Mock
    implements UpdateNotificationPreferencesUseCase {}

const _dep = Dependent(
  id: 'd1',
  firstName: 'Léo',
  lastName: 'Dubois',
  relationship: DependentRelationship.enfant,
);

const _pendingRequest = AccessRequest(
  id: 'ar1',
  firstName: 'Marie',
  lastName: 'Curie',
  relationship: DependentRelationship.conjoint,
  status: AccessRequestStatus.envoyee,
  channel: AccessRequestChannel.email,
);

const _consent = Consent(purpose: 'marketing', granted: false);

const _prefs = NotificationPreferences.allEnabled();

void main() {
  setUpAll(() {
    registerFallbackValue(DependentRelationship.enfant);
    registerFallbackValue(const NotificationPreferences.allEnabled());
  });

  group('DependentsCubit', () {
    late _MockList list;
    late _MockListAccessRequests listAccessRequests;
    late _MockGetUpcomingAppointments getUpcomingAppointments;
    late _MockAdd add;
    late _MockDelete del;
    late _MockResendAccessRequest resendAccessRequest;
    late _MockCancelAccessRequest cancelAccessRequest;
    late _MockGetAccount getAccount;

    setUp(() {
      list = _MockList();
      listAccessRequests = _MockListAccessRequests();
      getUpcomingAppointments = _MockGetUpcomingAppointments();
      add = _MockAdd();
      del = _MockDelete();
      resendAccessRequest = _MockResendAccessRequest();
      cancelAccessRequest = _MockCancelAccessRequest();
      getAccount = _MockGetAccount();
      when(() => listAccessRequests.call())
          .thenAnswer((_) async => const Right([]));
      when(() => getUpcomingAppointments.call())
          .thenAnswer((_) async => const Right([]));
      // Non couvert par ces tests (comportement de la carte titulaire,
      // cf. dependents_page_test.dart) : échoue pour garder `account: null`
      // et les états attendus ci-dessous inchangés.
      when(() => getAccount.call()).thenAnswer(
          (_) async => const Left(ServerFailure(message: 'n/a')));
    });

    blocTest<DependentsCubit, DependentsState>(
      'load → liste des proches',
      build: () {
        when(() => list.call()).thenAnswer((_) async => const Right([_dep]));
        return DependentsCubit(
          list: list,
          listAccessRequests: listAccessRequests,
          getUpcomingAppointments: getUpcomingAppointments,
          getAccount: getAccount,
          add: add,
          remove: del,
          resendAccessRequest: resendAccessRequest,
          cancelAccessRequest: cancelAccessRequest,
        );
      },
      act: (c) => c.load(),
      expect: () => [
        const DependentsLoading(),
        const DependentsLoaded([_dep]),
      ],
    );

    blocTest<DependentsCubit, DependentsState>(
      'load → encart d\'expiration visible si une demande est en attente',
      build: () {
        when(() => list.call()).thenAnswer((_) async => const Right([_dep]));
        when(() => listAccessRequests.call())
            .thenAnswer((_) async => const Right([_pendingRequest]));
        return DependentsCubit(
          list: list,
          listAccessRequests: listAccessRequests,
          getUpcomingAppointments: getUpcomingAppointments,
          getAccount: getAccount,
          add: add,
          remove: del,
          resendAccessRequest: resendAccessRequest,
          cancelAccessRequest: cancelAccessRequest,
        );
      },
      act: (c) => c.load(),
      expect: () => [
        const DependentsLoading(),
        const DependentsLoaded(
          [_dep],
          pendingAccessRequests: [_pendingRequest],
        ),
      ],
    );

    blocTest<DependentsCubit, DependentsState>(
      'add → recharge la liste après succès',
      build: () {
        when(() => add(
              firstName: any(named: 'firstName'),
              lastName: any(named: 'lastName'),
              birthDate: any(named: 'birthDate'),
              relationship: any(named: 'relationship'),
            )).thenAnswer((_) async => const Right(_dep));
        when(() => list.call()).thenAnswer((_) async => const Right([_dep]));
        return DependentsCubit(
          list: list,
          listAccessRequests: listAccessRequests,
          getUpcomingAppointments: getUpcomingAppointments,
          getAccount: getAccount,
          add: add,
          remove: del,
          resendAccessRequest: resendAccessRequest,
          cancelAccessRequest: cancelAccessRequest,
        );
      },
      seed: () => const DependentsLoaded([]),
      act: (c) => c.add(
        firstName: 'Léo',
        lastName: 'Dubois',
        relationship: DependentRelationship.enfant,
      ),
      verify: (_) {
        verify(() => add(
              firstName: 'Léo',
              lastName: 'Dubois',
              birthDate: null,
              relationship: DependentRelationship.enfant,
            )).called(1);
        verify(() => list.call()).called(1);
      },
    );

    blocTest<DependentsCubit, DependentsState>(
      'resend → relance la demande puis recharge',
      build: () {
        when(() => resendAccessRequest(any()))
            .thenAnswer((_) async => const Right(_pendingRequest));
        when(() => list.call()).thenAnswer((_) async => const Right([_dep]));
        return DependentsCubit(
          list: list,
          listAccessRequests: listAccessRequests,
          getUpcomingAppointments: getUpcomingAppointments,
          getAccount: getAccount,
          add: add,
          remove: del,
          resendAccessRequest: resendAccessRequest,
          cancelAccessRequest: cancelAccessRequest,
        );
      },
      seed: () => const DependentsLoaded([_dep]),
      act: (c) => c.resend('ar1'),
      verify: (_) {
        verify(() => resendAccessRequest('ar1')).called(1);
        verify(() => list.call()).called(1);
      },
    );

    blocTest<DependentsCubit, DependentsState>(
      'cancel → annule la demande puis recharge',
      build: () {
        when(() => cancelAccessRequest(any()))
            .thenAnswer((_) async => const Right(null));
        when(() => list.call()).thenAnswer((_) async => const Right([_dep]));
        return DependentsCubit(
          list: list,
          listAccessRequests: listAccessRequests,
          getUpcomingAppointments: getUpcomingAppointments,
          getAccount: getAccount,
          add: add,
          remove: del,
          resendAccessRequest: resendAccessRequest,
          cancelAccessRequest: cancelAccessRequest,
        );
      },
      seed: () => const DependentsLoaded([_dep]),
      act: (c) => c.cancel('ar1'),
      verify: (_) {
        verify(() => cancelAccessRequest('ar1')).called(1);
        verify(() => list.call()).called(1);
      },
    );
  });

  group('ConsentsCubit', () {
    late _MockListConsents list;
    late _MockSetConsent set;
    late _MockListPatientPharmacyOrders listPharmacyOrders;
    late _MockGetMyPharmacy getMyPharmacy;

    setUp(() {
      list = _MockListConsents();
      set = _MockSetConsent();
      listPharmacyOrders = _MockListPatientPharmacyOrders();
      getMyPharmacy = _MockGetMyPharmacy();
      when(() => getMyPharmacy()).thenAnswer((_) async => const Right(null));
    });

    blocTest<ConsentsCubit, ConsentsState>(
      'toggle → appelle setConsent puis recharge',
      build: () {
        when(() => set(
                purpose: any(named: 'purpose'), granted: any(named: 'granted')))
            .thenAnswer((_) async => const Right(null));
        when(() => list.call())
            .thenAnswer((_) async => const Right([_consent]));
        return ConsentsCubit(
          list: list,
          set: set,
          listPharmacyOrders: listPharmacyOrders,
          getMyPharmacy: getMyPharmacy,
        );
      },
      seed: () => const ConsentsLoaded([_consent]),
      act: (c) => c.toggle('marketing', true),
      verify: (_) {
        verify(() => set(purpose: 'marketing', granted: true)).called(1);
        verify(() => list.call()).called(1);
      },
    );
  });

  group('NotificationPrefsCubit', () {
    late _MockGetPrefs get;
    late _MockUpdatePrefs update;

    setUp(() {
      get = _MockGetPrefs();
      update = _MockUpdatePrefs();
    });

    blocTest<NotificationPrefsCubit, NotificationPrefsState>(
      'save échoue → rollback vers les préférences précédentes',
      build: () {
        when(() => update(any())).thenAnswer((_) async =>
            const Left(ServerFailure(message: 'boom', statusCode: 500)));
        return NotificationPrefsCubit(get: get, update: update);
      },
      seed: () => const NotificationPrefsLoaded(_prefs),
      act: (c) => c.save(_prefs.copyWith(pushEnabled: false)),
      expect: () => [
        NotificationPrefsLoaded(_prefs.copyWith(pushEnabled: false),
            saving: true),
        const NotificationPrefsError('boom'),
        const NotificationPrefsLoaded(_prefs),
      ],
    );
  });
}
