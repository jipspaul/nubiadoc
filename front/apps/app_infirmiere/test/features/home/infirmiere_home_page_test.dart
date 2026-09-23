// #7026 : accepter une offre ne donnait aucun retour visible — l'infirmière
// atterrissait sur l'état vide « Aucune offre » de l'onglet Offres, identique
// à celui affiché quand il n'y a jamais eu d'offre. Ce test vérifie qu'un
// accept réussi bascule automatiquement sur l'onglet « Ma visite » et affiche
// une confirmation explicite.
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_infirmiere/features/home/infirmiere_home_page.dart';
import 'package:app_infirmiere/features/notifications/notifications_bloc.dart';
import 'package:app_infirmiere/features/nurse/nurse_cubit.dart';

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

class FakeTokenStorage implements TokenStorage {
  @override
  Future<String?> getAccessToken() async => 'nurseToken';
  @override
  Future<String?> getRefreshToken() async => 'refreshToken';
  @override
  Future<String?> getFcmToken() async => null;
  @override
  Future<void> saveTokens({required String access, required String refresh}) async {}
  @override
  Future<void> saveFcmToken(String token) async {}
  @override
  Future<void> clearTokens() async {}
  @override
  Future<void> clearFcmToken() async {}
}

/// Scripte les endpoints `/nurse/*` consommés par [InfirmiereHomePage] au
/// montage ([NurseCubit.loadProfile]/`loadOffers`/`loadActiveVisit`) puis par
/// le tap sur « Accepter ».
class ScriptedNurseOffersAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    ResponseBody json(String body, [int status = 200]) => ResponseBody.fromString(
          body,
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );

    if (options.path == '/nurse/profile') {
      return json('{"is_online":true}');
    }
    if (options.path == '/nurse/offers') {
      return json('''
[{"id":"o1","requested_acts":["prise_de_sang"],
  "patient_display_name":"Marc D.",
  "address":{"city":"Lyon","postal_code":"69002"},
  "status":"offered","estimated_price_cents":4500,"notes":null}]
''');
    }
    if (options.path == '/nurse/visits' && options.method == 'GET') {
      return json('{}');
    }
    if (options.path == '/nurse/visits/o1/accept') {
      return json('''
{"id":"o1","requested_acts":["prise_de_sang"],
 "patient_display_name":"Marc D.",
 "address":{"line1":"1 place Bellecour","city":"Lyon","postal_code":"69002"},
 "status":"accepted","estimated_price_cents":4500,"notes":null}
''');
    }
    return json('{"error":"not_found"}', 404);
  }

  @override
  void close({bool force = false}) {}
}

/// Simule une coupure réseau : tous les appels `/v1/*` échouent, comme
/// `page.route('**/v1/**', r => r.abort())` dans le repro Playwright (#7530).
class NetworkDownAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'network is unreachable',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() async {
    await GetIt.instance.reset();

    final authInterceptor = AuthInterceptor(FakeTokenStorage());
    final api = ApiClient(authInterceptor)
      ..dio.httpClientAdapter = ScriptedNurseOffersAdapter();

    final notificationRepository = MockNotificationRepository();
    when(() => notificationRepository.getNotifications())
        .thenAnswer((_) async => const Right([]));

    GetIt.instance
      ..registerFactory<NurseCubit>(() => NurseCubit(api))
      ..registerFactory<NotificationsBloc>(
        () => NotificationsBloc(repository: notificationRepository),
      );
  });

  tearDown(() => GetIt.instance.reset());

  testWidgets(
      'accepter une offre bascule sur « Ma visite » et confirme le succès',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: InfirmiereHomePage()),
    );
    await tester.pumpAndSettle();

    // L'infirmière navigue vers l'onglet Offres, comme dans le repro.
    await tester.tap(find.text('Offres'));
    await tester.pumpAndSettle();

    expect(find.text('Marc D.'), findsOneWidget);
    expect(find.text('Aucune offre'), findsNothing);

    await tester.tap(find.text('Accepter'));
    await tester.pumpAndSettle();

    // L'onglet « Ma visite » est maintenant actif, la visite acceptée y est
    // visible, et l'écran ne retombe plus sur l'état vide « Aucune offre ».
    expect(find.text('Aucune offre'), findsNothing);
    expect(find.text('Statut : Acceptée'), findsOneWidget);
    expect(find.text('Offre acceptée — direction « Ma visite ».'),
        findsOneWidget);
  });

  testWidgets(
      'coupure réseau : la disponibilité est présentée comme inconnue, '
      'jamais comme "hors ligne" affirmé (#7530)', (tester) async {
    // Ré-enregistre le NurseCubit sur un client qui échoue systématiquement,
    // pour reproduire la coupure réseau du repro (page.route(...).abort()).
    await GetIt.instance.reset();
    final authInterceptor = AuthInterceptor(FakeTokenStorage());
    final api = ApiClient(authInterceptor)
      ..dio.httpClientAdapter = NetworkDownAdapter();
    final notificationRepository = MockNotificationRepository();
    when(() => notificationRepository.getNotifications())
        .thenAnswer((_) async => const Right([]));
    GetIt.instance
      ..registerFactory<NurseCubit>(() => NurseCubit(api))
      ..registerFactory<NotificationsBloc>(
        () => NotificationsBloc(repository: notificationRepository),
      );

    await tester.pumpWidget(
      const MaterialApp(home: InfirmiereHomePage()),
    );
    await tester.pumpAndSettle();

    // Jamais l'affirmation d'un "hors ligne" métier non lu depuis le serveur.
    expect(
      find.text('Vous êtes hors ligne. Passez en ligne pour recevoir des demandes.'),
      findsNothing,
    );
    expect(
      find.text(
          'Disponibilité indisponible — impossible de joindre le serveur.'),
      findsOneWidget,
    );

    final switchTile = tester
        .widget<SwitchListTile>(find.byKey(const Key('availability_switch')));
    expect(switchTile.value, isFalse);
    expect(switchTile.onChanged, isNull);
  });
}
