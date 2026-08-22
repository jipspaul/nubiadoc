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

class _MockAdd extends Mock implements AddDependentUseCase {}

class _MockDelete extends Mock implements DeleteDependentUseCase {}

class _MockListConsents extends Mock implements ListConsentsUseCase {}

class _MockSetConsent extends Mock implements SetConsentUseCase {}

class _MockGetPrefs extends Mock implements GetNotificationPreferencesUseCase {}

class _MockUpdatePrefs extends Mock
    implements UpdateNotificationPreferencesUseCase {}

const _dep = Dependent(
  id: 'd1',
  firstName: 'Léo',
  lastName: 'Dubois',
  relationship: DependentRelationship.enfant,
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
    late _MockAdd add;
    late _MockDelete del;

    setUp(() {
      list = _MockList();
      listAccessRequests = _MockListAccessRequests();
      add = _MockAdd();
      del = _MockDelete();
      when(() => listAccessRequests.call())
          .thenAnswer((_) async => const Right([]));
    });

    blocTest<DependentsCubit, DependentsState>(
      'load → liste des proches',
      build: () {
        when(() => list.call()).thenAnswer((_) async => const Right([_dep]));
        return DependentsCubit(
          list: list,
          listAccessRequests: listAccessRequests,
          add: add,
          remove: del,
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
        when(() => listAccessRequests.call()).thenAnswer(
          (_) async => const Right([
            AccessRequest(
              id: 'ar1',
              firstName: 'Marie',
              lastName: 'Curie',
              relationship: DependentRelationship.conjoint,
              status: AccessRequestStatus.envoyee,
              channel: AccessRequestChannel.email,
            ),
          ]),
        );
        return DependentsCubit(
          list: list,
          listAccessRequests: listAccessRequests,
          add: add,
          remove: del,
        );
      },
      act: (c) => c.load(),
      expect: () => [
        const DependentsLoading(),
        const DependentsLoaded([_dep], hasPendingAccessRequest: true),
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
          add: add,
          remove: del,
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
  });

  group('ConsentsCubit', () {
    late _MockListConsents list;
    late _MockSetConsent set;

    setUp(() {
      list = _MockListConsents();
      set = _MockSetConsent();
    });

    blocTest<ConsentsCubit, ConsentsState>(
      'toggle → appelle setConsent puis recharge',
      build: () {
        when(() => set(
                purpose: any(named: 'purpose'), granted: any(named: 'granted')))
            .thenAnswer((_) async => const Right(null));
        when(() => list.call())
            .thenAnswer((_) async => const Right([_consent]));
        return ConsentsCubit(list: list, set: set);
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
