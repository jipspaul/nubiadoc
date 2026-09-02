import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_pharmacie/session/pharma_auth_cubit.dart';

/// Construit un JWT factice (payload seul lisible, signature bidon) pour
/// tester la lecture locale de `kind` sans dépendre d'un vrai secret.
String _fakeJwt(Map<String, dynamic> payload) {
  final segment =
      base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return 'header.$segment.signature';
}

class MockLoginUseCase extends Mock implements LoginUseCase {}

class MockLogoutUseCase extends Mock implements LogoutUseCase {}

class MockTokenStorage extends Mock implements TokenStorage {}

class MockDeviceRegistrationService extends Mock
    implements DeviceRegistrationService {}

class MockGetPharmacyMembershipsUseCase extends Mock
    implements GetPharmacyMembershipsUseCase {}

class MockSelectPharmacyContextUseCase extends Mock
    implements SelectPharmacyContextUseCase {}

void main() {
  late MockLoginUseCase login;
  late MockLogoutUseCase logout;
  late MockTokenStorage tokenStorage;
  late MockDeviceRegistrationService deviceRegistration;
  late MockGetPharmacyMembershipsUseCase memberships;
  late MockSelectPharmacyContextUseCase selectContext;

  const membership = PharmacyMembership(
    pharmacyId: 'f0000000-0000-0000-0000-0000000000f1',
    role: 'pharmacist',
    name: 'Pharmacie du Rhône',
  );
  const context = PharmacyContext(
    pharmacyId: 'f0000000-0000-0000-0000-0000000000f1',
    role: 'pharmacist',
    name: 'Pharmacie du Rhône',
  );
  final account =
      PatientAccount(id: '', firstName: '', lastName: '', email: 'p@o.fr');

  PharmaAuthCubit buildCubit() => PharmaAuthCubit(
        login: login,
        logout: logout,
        tokenStorage: tokenStorage,
        deviceRegistration: deviceRegistration,
        memberships: memberships,
        selectContext: selectContext,
        app: 'pharmacie',
      );

  setUp(() {
    login = MockLoginUseCase();
    logout = MockLogoutUseCase();
    tokenStorage = MockTokenStorage();
    deviceRegistration = MockDeviceRegistrationService();
    memberships = MockGetPharmacyMembershipsUseCase();
    selectContext = MockSelectPharmacyContextUseCase();

    when(() =>
            login(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => Right(account));
    when(() => logout()).thenAnswer((_) async => const Right(null));
    when(() => deviceRegistration.registerOnLogin(any()))
        .thenAnswer((_) async {});
    when(() => memberships()).thenAnswer(
      (_) async => const Right(
        (displayName: 'Jean Officine', memberships: [membership]),
      ),
    );
    when(() => selectContext(any()))
        .thenAnswer((_) async => const Right(context));
  });

  group('signIn', () {
    blocTest<PharmaAuthCubit, AuthState>(
      'login + membership + contexte → Authenticated (rôle pharmacien)',
      build: buildCubit,
      act: (cubit) => cubit.signIn(email: 'p@o.fr', password: 'x'),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>().having(
          (s) => s.session.role,
          'role',
          ProRole.pharmacist,
        ),
      ],
      verify: (_) {
        verify(() => selectContext(membership.pharmacyId)).called(1);
        verify(() => deviceRegistration.registerOnLogin('pharmacie')).called(1);
      },
    );

    blocTest<PharmaAuthCubit, AuthState>(
      'aucune appartenance pharmacie → déconnexion + message explicite',
      build: buildCubit,
      setUp: () {
        when(() => memberships()).thenAnswer(
          (_) async => const Right(
            (displayName: null, memberships: <PharmacyMembership>[]),
          ),
        );
      },
      act: (cubit) => cubit.signIn(email: 'patient@x.fr', password: 'x'),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>().having(
          (s) => s.message,
          'message',
          contains('Aucun espace pharmacie'),
        ),
      ],
      verify: (_) {
        verify(() => logout()).called(1);
        verifyNever(() => selectContext(any()));
        verifyNever(() => deviceRegistration.registerOnLogin(any()));
      },
    );

    blocTest<PharmaAuthCubit, AuthState>(
      'échec de select-pharmacy-context → Unauthenticated avec message',
      build: buildCubit,
      setUp: () {
        when(() => selectContext(any())).thenAnswer(
          (_) async => const Left(
            ServerFailure(
              message: 'Ce compte n’a pas accès à cette pharmacie.',
              statusCode: 403,
              code: 'no_membership',
            ),
          ),
        );
      },
      act: (cubit) => cubit.signIn(email: 'p@o.fr', password: 'x'),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>()
            .having((s) => s.message, 'message', contains('pas accès')),
      ],
    );

    blocTest<PharmaAuthCubit, AuthState>(
      'identifiants invalides → Unauthenticated, aucun appel contexte',
      build: buildCubit,
      setUp: () {
        when(() => login(
                email: any(named: 'email'), password: any(named: 'password')))
            .thenAnswer((_) async => const Left(InvalidCredentialsFailure()));
      },
      act: (cubit) => cubit.signIn(email: 'p@o.fr', password: 'bad'),
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
      verify: (_) {
        verifyNever(() => memberships());
        verifyNever(() => selectContext(any()));
      },
    );
  });

  group('restore', () {
    blocTest<PharmaAuthCubit, AuthState>(
      'token présent → contexte re-sélectionné → Authenticated',
      build: buildCubit,
      setUp: () {
        when(() => tokenStorage.getAccessToken())
            .thenAnswer((_) async => 'stored-token');
      },
      act: (cubit) => cubit.restore(),
      expect: () => [isA<AuthAuthenticated>()],
      verify: (_) {
        verify(() => selectContext(membership.pharmacyId)).called(1);
      },
    );

    blocTest<PharmaAuthCubit, AuthState>(
      'aucun token → Unauthenticated sans message',
      build: buildCubit,
      setUp: () {
        when(() => tokenStorage.getAccessToken()).thenAnswer((_) async => null);
      },
      act: (cubit) => cubit.restore(),
      expect: () => [
        isA<AuthUnauthenticated>().having((s) => s.message, 'message', isNull),
      ],
    );

    blocTest<PharmaAuthCubit, AuthState>(
      'session périmée (memberships en échec) → Unauthenticated silencieux',
      build: buildCubit,
      setUp: () {
        when(() => tokenStorage.getAccessToken())
            .thenAnswer((_) async => 'stale-token');
        when(() => memberships())
            .thenAnswer((_) async => const Left(UnauthorizedFailure()));
      },
      act: (cubit) => cubit.restore(),
      expect: () => [
        isA<AuthUnauthenticated>().having((s) => s.message, 'message', isNull),
      ],
    );

    // #4531 : le token persisté est déjà kind:"pharma" (select-pharmacy-context
    // ou onTokensRefreshed l'a écrasé lors de la session précédente) — ne
    // JAMAIS rejouer select-pharmacy-context avec ce token (403 côté back,
    // cf. ProClaims), restaurer directement depuis /v1/me.
    blocTest<PharmaAuthCubit, AuthState>(
      'token déjà kind:"pharma" → restauration directe, sans re-sélection',
      build: buildCubit,
      setUp: () {
        when(() => tokenStorage.getAccessToken()).thenAnswer(
          (_) async => _fakeJwt({'sub': 'u1', 'kind': 'pharma', 'exp': 0}),
        );
      },
      act: (cubit) => cubit.restore(),
      expect: () => [
        isA<AuthAuthenticated>().having(
          (s) => s.session.role,
          'role',
          ProRole.pharmacist,
        ),
      ],
      verify: (_) {
        verify(() => memberships()).called(1);
        verifyNever(() => selectContext(any()));
      },
    );

    blocTest<PharmaAuthCubit, AuthState>(
      'token kind:"pharma" mais memberships vide → Unauthenticated',
      build: buildCubit,
      setUp: () {
        when(() => tokenStorage.getAccessToken()).thenAnswer(
          (_) async => _fakeJwt({'sub': 'u1', 'kind': 'pharma', 'exp': 0}),
        );
        when(() => memberships()).thenAnswer(
          (_) async => const Right(
            (displayName: null, memberships: <PharmacyMembership>[]),
          ),
        );
      },
      act: (cubit) => cubit.restore(),
      expect: () => [
        isA<AuthUnauthenticated>().having((s) => s.message, 'message', isNull),
      ],
      verify: (_) {
        verifyNever(() => selectContext(any()));
      },
    );
  });
}
