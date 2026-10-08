// #7026 : accepter une offre ne donnait aucun retour visible — l'infirmière
// atterrissait sur l'état vide « Aucune offre » de l'onglet Offres, identique
// à celui affiché quand il n'y a jamais eu d'offre. Ce test vérifie qu'un
// accept réussi bascule automatiquement sur l'onglet « Ma visite » et affiche
// une confirmation explicite.
import 'dart:async';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
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

/// Démarre hors ligne puis retarde le PATCH `/nurse/availability` jusqu'à ce
/// que le test appelle [respond] — reproduit la fenêtre de latence du repro
/// #8086 pour vérifier que l'UI donne un retour pendant l'attente.
class DelayedAvailabilityAdapter implements HttpClientAdapter {
  final _pending = Completer<void>();

  void respond() => _pending.complete();

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
      return json('{"is_online":false}');
    }
    if (options.path == '/nurse/offers') {
      return json('[]');
    }
    if (options.path == '/nurse/visits' && options.method == 'GET') {
      return json('{}');
    }
    if (options.path == '/nurse/availability') {
      await _pending.future;
      return json('{}');
    }
    return json('{"error":"not_found"}', 404);
  }

  @override
  void close({bool force = false}) {}
}

/// Retarde la réponse de `GET /nurse/visits` jusqu'à ce que le test appelle
/// [respond] — reproduit la fenêtre de latence entre le montage de l'écran
/// et la résolution de `loadActiveVisit` (variante "lenteur réseau" du
/// repro #8147). `/nurse/profile` et `/nurse/offers` répondent aussitôt.
class DelayedVisitAdapter implements HttpClientAdapter {
  final _pending = Completer<void>();

  void respond() => _pending.complete();

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
      return json('[]');
    }
    if (options.path == '/nurse/visits' && options.method == 'GET') {
      await _pending.future;
      return json('''
{"id":"v1","requested_acts":["pansement"],
 "patient_display_name":"Marc D.",
 "address":{"line1":"20 rue de la Part-Dieu","city":"Lyon"},
 "status":"accepted","estimated_price_cents":4500,"notes":null}
''');
    }
    return json('{"error":"not_found"}', 404);
  }

  @override
  void close({bool force = false}) {}
}

/// Échoue une première fois sur `GET /nurse/visits` (coupure réseau), puis
/// répond avec succès dès le prochain appel — permet de vérifier le bouton
/// « Réessayer » de l'état d'erreur (#8147).
class FailOnceThenSucceedVisitAdapter implements HttpClientAdapter {
  var _visitCalls = 0;

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
      return json('[]');
    }
    if (options.path == '/nurse/visits' && options.method == 'GET') {
      _visitCalls++;
      if (_visitCalls == 1) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'network is unreachable',
        );
      }
      return json('''
{"id":"v1","requested_acts":["pansement"],
 "patient_display_name":"Marc D.",
 "address":{"line1":"20 rue de la Part-Dieu","city":"Lyon"},
 "status":"accepted","estimated_price_cents":4500,"notes":null}
''');
    }
    return json('{"error":"not_found"}', 404);
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
      MaterialApp(theme: NubiaTheme.light, home: const InfirmiereHomePage()),
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
      MaterialApp(theme: NubiaTheme.light, home: const InfirmiereHomePage()),
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

  testWidgets(
      'basculer "En ligne" donne un retour visuel immédiat et désactive la '
      'bascule pendant l\'appel, au lieu des 9,15 s silencieuses du repro '
      '(#8086)', (tester) async {
    await GetIt.instance.reset();
    final authInterceptor = AuthInterceptor(FakeTokenStorage());
    final adapter = DelayedAvailabilityAdapter();
    final api = ApiClient(authInterceptor)..dio.httpClientAdapter = adapter;
    final notificationRepository = MockNotificationRepository();
    when(() => notificationRepository.getNotifications())
        .thenAnswer((_) async => const Right([]));
    GetIt.instance
      ..registerFactory<NurseCubit>(() => NurseCubit(api))
      ..registerFactory<NotificationsBloc>(
        () => NotificationsBloc(repository: notificationRepository),
      );

    await tester.pumpWidget(
      MaterialApp(theme: NubiaTheme.light, home: const InfirmiereHomePage()),
    );
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('availability_switch'));
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pump();

    // Retour visuel immédiat, avant toute réponse serveur : bascule
    // optimiste à ON et désactivée pendant l'appel (plus aucun silence de
    // plusieurs secondes sans le moindre signal).
    final pending = tester.widget<SwitchListTile>(switchFinder);
    expect(pending.value, isTrue);
    expect(pending.onChanged, isNull);
    expect(find.text('Mise à jour en cours…'), findsOneWidget);

    adapter.respond();
    await tester.pumpAndSettle();

    final done = tester.widget<SwitchListTile>(switchFinder);
    expect(done.value, isTrue);
    expect(done.onChanged, isNotNull);
    expect(find.text('Mise à jour en cours…'), findsNothing);

    // `setOnline` pousse la position en tâche de fond (non bloquant pour
    // l'UI, déjà vérifiée ci-dessus) : on laisse son timeout de
    // géolocalisation (8 s, horloge virtuelle de `pump`) s'écouler pour ne
    // pas quitter le test avec un minuteur encore en attente.
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets(
      '« Ma visite » affiche un chargement, jamais le faux état vide, '
      'tant que GET /nurse/visits n\'a pas répondu (#8147)', (tester) async {
    await GetIt.instance.reset();
    final authInterceptor = AuthInterceptor(FakeTokenStorage());
    final adapter = DelayedVisitAdapter();
    final api = ApiClient(authInterceptor)..dio.httpClientAdapter = adapter;
    final notificationRepository = MockNotificationRepository();
    when(() => notificationRepository.getNotifications())
        .thenAnswer((_) async => const Right([]));
    GetIt.instance
      ..registerFactory<NurseCubit>(() => NurseCubit(api))
      ..registerFactory<NotificationsBloc>(
        () => NotificationsBloc(repository: notificationRepository),
      );

    await tester.pumpWidget(
      MaterialApp(theme: NubiaTheme.light, home: const InfirmiereHomePage()),
    );
    await tester.pump();

    await tester.tap(find.text('Ma visite'));
    await tester.pump();

    // La requête serveur n'a pas encore répondu : l'écran doit montrer un
    // chargement, jamais l'état vide affirmatif (qui masquerait les 3
    // transitions d'une visite pourtant acceptée côté serveur).
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Aucune visite en cours'), findsNothing);

    adapter.respond();
    await tester.pumpAndSettle();

    expect(find.text('Statut : Acceptée'), findsOneWidget);
    expect(find.text('Je pars'), findsOneWidget);
    expect(find.text('Aucune visite en cours'), findsNothing);
  });

  testWidgets(
      '« Ma visite » affiche une erreur avec un bouton Réessayer (jamais le '
      'faux état vide) quand GET /nurse/visits échoue (#8147)',
      (tester) async {
    await GetIt.instance.reset();
    final authInterceptor = AuthInterceptor(FakeTokenStorage());
    final adapter = FailOnceThenSucceedVisitAdapter();
    final api = ApiClient(authInterceptor)..dio.httpClientAdapter = adapter;
    final notificationRepository = MockNotificationRepository();
    when(() => notificationRepository.getNotifications())
        .thenAnswer((_) async => const Right([]));
    GetIt.instance
      ..registerFactory<NurseCubit>(() => NurseCubit(api))
      ..registerFactory<NotificationsBloc>(
        () => NotificationsBloc(repository: notificationRepository),
      );

    await tester.pumpWidget(
      MaterialApp(theme: NubiaTheme.light, home: const InfirmiereHomePage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ma visite'));
    await tester.pumpAndSettle();

    expect(find.text('Aucune visite en cours'), findsNothing);
    expect(find.text('Impossible de charger votre visite'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();

    expect(find.text('Statut : Acceptée'), findsOneWidget);
    expect(find.text('Je pars'), findsOneWidget);
  });
}
