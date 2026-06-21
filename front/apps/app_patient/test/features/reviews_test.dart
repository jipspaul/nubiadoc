import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/reviews/reviews_bloc.dart';
import 'package:app_patient/features/reviews/reviews_event.dart';
import 'package:app_patient/features/reviews/reviews_page.dart';
import 'package:app_patient/features/reviews/reviews_state.dart';
import 'package:app_patient/features/notifications/notifications_bloc.dart';
import 'package:app_patient/features/notifications/notifications_event.dart';
import 'package:app_patient/features/notifications/notifications_page.dart';
import 'package:app_patient/features/notifications/notifications_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetProviderReviewsUseCase extends Mock
    implements GetProviderReviewsUseCase {}

class MockSubmitReviewUseCase extends Mock implements SubmitReviewUseCase {}

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _review = Review(
  id: 'rev-1',
  providerId: 'prov-1',
  appointmentId: 'appt-1',
  rating: 4,
  comment: 'Très bonne prise en charge.',
  authorName: 'Alice Martin',
  createdAt: DateTime(2026, 6, 1),
  status: ReviewStatus.published,
);

final _notification = AppNotification(
  id: 'notif-1',
  type: NotificationType.appointment,
  title: 'Rappel RDV',
  body: 'Votre rendez-vous est demain.',
  read: false,
  createdAt: DateTime(2026, 6, 10),
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ReviewsBloc _makeReviewsBloc({
  required MockGetProviderReviewsUseCase getProviderReviews,
  required MockSubmitReviewUseCase submitReview,
}) =>
    ReviewsBloc(
      getProviderReviews: getProviderReviews,
      submitReview: submitReview,
    );

NotificationsBloc _makeNotificationsBloc({
  required MockNotificationRepository repository,
}) =>
    NotificationsBloc(repository: repository);

Widget _wrapReviews(ReviewsBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: ReviewsPage()),
      ),
    );

Widget _wrapNotifications(NotificationsBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: NotificationsPage()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests — Reviews
// ---------------------------------------------------------------------------

void main() {
  late MockGetProviderReviewsUseCase mockGetReviews;
  late MockSubmitReviewUseCase mockSubmitReview;
  late MockNotificationRepository mockNotifRepo;

  setUp(() {
    mockGetReviews = MockGetProviderReviewsUseCase();
    mockSubmitReview = MockSubmitReviewUseCase();
    mockNotifRepo = MockNotificationRepository();
  });

  group('ReviewsPage widget', () {
    testWidgets('affiche le spinner en état chargement', (tester) async {
      final bloc = _makeReviewsBloc(
        getProviderReviews: mockGetReviews,
        submitReview: mockSubmitReview,
      );

      await tester.pumpWidget(_wrapReviews(bloc));

      expect(find.byKey(const Key('reviews_loading')), findsOneWidget);
    });

    testWidgets('affiche "Aucun avis" quand la liste est vide', (tester) async {
      when(() => mockGetReviews(any()))
          .thenAnswer((_) async => const Right([]));

      final bloc = _makeReviewsBloc(
        getProviderReviews: mockGetReviews,
        submitReview: mockSubmitReview,
      );
      bloc.add(const ReviewsLoadRequested('prov-1'));

      await tester.pumpWidget(_wrapReviews(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reviews_empty')), findsOneWidget);
    });

    testWidgets('affiche les avis chargés', (tester) async {
      when(() => mockGetReviews(any()))
          .thenAnswer((_) async => Right([_review]));

      final bloc = _makeReviewsBloc(
        getProviderReviews: mockGetReviews,
        submitReview: mockSubmitReview,
      );
      bloc.add(const ReviewsLoadRequested('prov-1'));

      await tester.pumpWidget(_wrapReviews(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reviews_list')), findsOneWidget);
      expect(find.text('Alice Martin'), findsOneWidget);
    });

    testWidgets('pull-to-refresh dispatch ReviewsLoadRequested', (tester) async {
      when(() => mockGetReviews(any()))
          .thenAnswer((_) async => Right([_review]));

      final bloc = _makeReviewsBloc(
        getProviderReviews: mockGetReviews,
        submitReview: mockSubmitReview,
      );
      bloc.add(const ReviewsLoadRequested('prov-1'));

      await tester.pumpWidget(_wrapReviews(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reviews_list')), findsOneWidget);

      await tester.drag(
          find.byKey(const Key('reviews_list')), const Offset(0, 400));
      await tester.pumpAndSettle();

      verify(() => mockGetReviews(any())).called(greaterThanOrEqualTo(2));
    });

    testWidgets('affiche le message d\'erreur en état erreur', (tester) async {
      when(() => mockGetReviews(any())).thenAnswer(
        (_) async => const Left(NetworkFailure('Erreur réseau.')),
      );

      final bloc = _makeReviewsBloc(
        getProviderReviews: mockGetReviews,
        submitReview: mockSubmitReview,
      );
      bloc.add(const ReviewsLoadRequested('prov-1'));

      await tester.pumpWidget(_wrapReviews(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reviews_error')), findsOneWidget);
      expect(find.text('Erreur réseau.'), findsOneWidget);
    });
  });

  group('ReviewsBloc', () {
    blocTest<ReviewsBloc, ReviewsState>(
      'émet [Loading, Loaded(vide)] quand la liste est vide',
      build: () {
        when(() => mockGetReviews(any()))
            .thenAnswer((_) async => const Right([]));
        return _makeReviewsBloc(
          getProviderReviews: mockGetReviews,
          submitReview: mockSubmitReview,
        );
      },
      act: (bloc) => bloc.add(const ReviewsLoadRequested('prov-1')),
      expect: () => [
        const ReviewsLoading(),
        isA<ReviewsLoaded>().having((s) => s.reviews, 'reviews', isEmpty),
      ],
    );

    blocTest<ReviewsBloc, ReviewsState>(
      'émet [Loading, Loaded] avec les avis',
      build: () {
        when(() => mockGetReviews(any()))
            .thenAnswer((_) async => Right([_review]));
        return _makeReviewsBloc(
          getProviderReviews: mockGetReviews,
          submitReview: mockSubmitReview,
        );
      },
      act: (bloc) => bloc.add(const ReviewsLoadRequested('prov-1')),
      expect: () => [
        const ReviewsLoading(),
        isA<ReviewsLoaded>()
            .having((s) => s.reviews.length, 'length', 1)
            .having((s) => s.reviews.first.id, 'id', 'rev-1'),
      ],
    );

    blocTest<ReviewsBloc, ReviewsState>(
      'émet [Loading, Error] quand le chargement échoue',
      build: () {
        when(() => mockGetReviews(any())).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau.')),
        );
        return _makeReviewsBloc(
          getProviderReviews: mockGetReviews,
          submitReview: mockSubmitReview,
        );
      },
      act: (bloc) => bloc.add(const ReviewsLoadRequested('prov-1')),
      expect: () => [
        const ReviewsLoading(),
        isA<ReviewsError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );
  });

  // --------------------------------------------------------------------------
  // Tests — NotificationsPage
  // --------------------------------------------------------------------------

  group('NotificationsPage widget', () {
    testWidgets('affiche le spinner en état chargement', (tester) async {
      final bloc = _makeNotificationsBloc(repository: mockNotifRepo);

      await tester.pumpWidget(_wrapNotifications(bloc));

      expect(find.byKey(const Key('notifications_loading')), findsOneWidget);
    });

    testWidgets('affiche "Aucune notification" quand la liste est vide',
        (tester) async {
      when(() => mockNotifRepo.getNotifications())
          .thenAnswer((_) async => const Right([]));

      final bloc = _makeNotificationsBloc(repository: mockNotifRepo);
      bloc.add(const NotificationsLoadRequested());

      await tester.pumpWidget(_wrapNotifications(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
    });

    testWidgets('affiche les notifications chargées', (tester) async {
      when(() => mockNotifRepo.getNotifications())
          .thenAnswer((_) async => Right([_notification]));

      final bloc = _makeNotificationsBloc(repository: mockNotifRepo);
      bloc.add(const NotificationsLoadRequested());

      await tester.pumpWidget(_wrapNotifications(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_list')), findsOneWidget);
      expect(find.byKey(const Key('notif_notif-1')), findsOneWidget);
    });
  });

  group('NotificationsBloc', () {
    blocTest<NotificationsBloc, NotificationsState>(
      'émet [Loading, Loaded(vide)] quand la liste est vide',
      build: () {
        when(() => mockNotifRepo.getNotifications())
            .thenAnswer((_) async => const Right([]));
        return _makeNotificationsBloc(repository: mockNotifRepo);
      },
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => [
        const NotificationsLoading(),
        isA<NotificationsLoaded>()
            .having((s) => s.notifications, 'notifications', isEmpty),
      ],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet [Loading, Loaded] avec les notifications',
      build: () {
        when(() => mockNotifRepo.getNotifications())
            .thenAnswer((_) async => Right([_notification]));
        return _makeNotificationsBloc(repository: mockNotifRepo);
      },
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => [
        const NotificationsLoading(),
        isA<NotificationsLoaded>()
            .having((s) => s.notifications.length, 'length', 1)
            .having((s) => s.unreadCount, 'unreadCount', 1),
      ],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet [Loading, Error] quand le chargement échoue',
      build: () {
        when(() => mockNotifRepo.getNotifications()).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau.')),
        );
        return _makeNotificationsBloc(repository: mockNotifRepo);
      },
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => [
        const NotificationsLoading(),
        isA<NotificationsError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'marque une notification comme lue (mise à jour optimiste)',
      build: () {
        when(() => mockNotifRepo.markRead(any()))
            .thenAnswer((_) async => const Right(null));
        return _makeNotificationsBloc(repository: mockNotifRepo);
      },
      seed: () => NotificationsLoaded([_notification]),
      act: (bloc) =>
          bloc.add(const NotificationMarkReadRequested('notif-1')),
      expect: () => [
        isA<NotificationsLoaded>().having(
          (s) => s.notifications.first.read,
          'read',
          true,
        ),
      ],
    );
  });
}
