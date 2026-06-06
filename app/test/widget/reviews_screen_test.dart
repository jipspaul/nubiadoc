import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/entities/review.dart';
import 'package:nubia_patient/presentation/features/reviews/bloc/reviews_bloc.dart';
import 'package:nubia_patient/presentation/features/reviews/widgets/review_card.dart';
import 'package:nubia_patient/presentation/features/reviews/widgets/review_submit_form.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

class MockReviewsBloc extends MockBloc<ReviewsEvent, ReviewsState>
    implements ReviewsBloc {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Review _makeReview(String id) => Review(
      id: id,
      providerId: 'prov-1',
      appointmentId: 'appt-$id',
      rating: 4,
      comment: 'Très bien',
      authorName: 'Alice',
      createdAt: DateTime(2026, 1, 15),
      status: ReviewStatus.published,
    );

Appointment _makeAppointment(String id) => Appointment(
      id: id,
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Martin',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().subtract(const Duration(days: 10)),
      duration: const Duration(minutes: 30),
      motif: 'Contrôle annuel',
      status: AppointmentStatus.completed,
    );

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrapWithBloc(
  MockReviewsBloc bloc, {
  List<Appointment> honoredAppointments = const [],
}) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<ReviewsBloc>.value(
      value: bloc,
      child: _ReviewsBodyUnwrapped(honoredAppointments: honoredAppointments),
    ),
  );
}

/// Mirrors the internal body of ReviewsScreen without DI to allow mock
/// injection in tests.
class _ReviewsBodyUnwrapped extends StatelessWidget {
  const _ReviewsBodyUnwrapped({required this.honoredAppointments});

  final List<Appointment> honoredAppointments;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Avis')),
      body: BlocBuilder<ReviewsBloc, ReviewsState>(
        builder: (context, state) {
          if (state is ReviewsInitial || state is ReviewsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ReviewsError) {
            return Center(child: Text(state.message));
          }

          final reviews = state is ReviewsLoaded ? state.reviews : const <Review>[];
          final isSubmitting = state is ReviewSubmitting;

          return ListView(
            children: [
              if (honoredAppointments.isNotEmpty) ...[
                ReviewSubmitForm(
                  honoredAppointments: honoredAppointments,
                  isSubmitting: isSubmitting,
                  onSubmit: (appointmentId, rating, comment) {
                    context.read<ReviewsBloc>().add(
                          ReviewSubmitRequested(
                            appointmentId: appointmentId,
                            rating: rating,
                            comment: comment,
                            idempotencyKey: 'test-key',
                          ),
                        );
                  },
                ),
              ],
              ...reviews.map((r) => ReviewCard(review: r)),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockReviewsBloc bloc;

  setUpAll(() async {
    await initializeDateFormatting('fr');
    registerFallbackValue(const ReviewsLoadRequested(''));
    registerFallbackValue(
      const ReviewSubmitRequested(
        appointmentId: '',
        rating: 1,
        idempotencyKey: '',
      ),
    );
  });

  setUp(() {
    bloc = MockReviewsBloc();
  });

  tearDown(() => bloc.close());

  testWidgets('affiche un indicateur de chargement en état Loading',
      (tester) async {
    when(() => bloc.state).thenReturn(const ReviewsLoading());

    await tester.pumpWidget(_wrapWithBloc(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('affiche un message d\'erreur en état Error', (tester) async {
    when(() => bloc.state)
        .thenReturn(const ReviewsError('Erreur réseau.'));

    await tester.pumpWidget(_wrapWithBloc(bloc));

    expect(find.text('Erreur réseau.'), findsOneWidget);
  });

  testWidgets('affiche la liste des avis en état Loaded', (tester) async {
    final reviews = [_makeReview('r1'), _makeReview('r2')];
    when(() => bloc.state).thenReturn(ReviewsLoaded(reviews));

    await tester.pumpWidget(_wrapWithBloc(bloc));

    expect(find.byType(ReviewCard), findsNWidgets(2));
    expect(find.text('Très bien'), findsNWidgets(2));
  });

  testWidgets('soumission d\'avis déclenche ReviewSubmitRequested',
      (tester) async {
    final appointment = _makeAppointment('appt-1');
    when(() => bloc.state).thenReturn(const ReviewsLoaded([]));

    await tester.pumpWidget(
      _wrapWithBloc(bloc, honoredAppointments: [appointment]),
    );

    // Select appointment in the dropdown
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Martin — Contrôle annuel').last);
    await tester.pumpAndSettle();

    // Select rating 4 stars
    await tester.tap(find.byKey(const Key('star_4')));
    await tester.pump();

    // Tap submit
    await tester.tap(find.byKey(const Key('submit_review')));
    await tester.pump();

    verify(
      () => bloc.add(
        any(
          that: isA<ReviewSubmitRequested>()
              .having((e) => e.appointmentId, 'appointmentId', 'appt-1')
              .having((e) => e.rating, 'rating', 4),
        ),
      ),
    ).called(1);
  });
}
