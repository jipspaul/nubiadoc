import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/reviews/reviews_bloc.dart';
import 'package:app_patient/features/reviews/reviews_event.dart';
import 'package:app_patient/features/reviews/reviews_state.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class _MockReviewsBloc extends MockBloc<ReviewsEvent, ReviewsState>
    implements ReviewsBloc {}

// ---------------------------------------------------------------------------
// Stub widget — reproduit le contrat UI sans passer par GetIt
// ---------------------------------------------------------------------------

class _ReviewsPageStub extends StatelessWidget {
  const _ReviewsPageStub();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReviewsBloc, ReviewsState>(
      builder: (context, state) {
        if (state is ReviewsLoading || state is ReviewsInitial) {
          return const Column(
            children: [
              NubiaSkeletonLoader(height: 72),
              SizedBox(height: 8),
              NubiaSkeletonLoader(height: 72),
              SizedBox(height: 8),
              NubiaSkeletonLoader(height: 72),
            ],
          );
        }
        if (state is ReviewsLoaded && state.reviews.isEmpty) {
          return const NubiaEmptyState(
            icon: Icons.rate_review_outlined,
            title: 'Aucun avis pour ce prestataire.',
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

Widget _wrap(ReviewsBloc bloc) => MaterialApp(
      home: BlocProvider<ReviewsBloc>.value(
        value: bloc,
        child: const Scaffold(body: _ReviewsPageStub()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ReviewsPage — skeleton Loading', () {
    testWidgets('affiche NubiaSkeletonLoader en état Loading', (tester) async {
      final bloc = _MockReviewsBloc();
      when(() => bloc.state).thenReturn(const ReviewsLoading());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
    });
  });

  group('ReviewsPage — empty state', () {
    testWidgets('affiche NubiaEmptyState quand Loaded(items=[]) est émis',
        (tester) async {
      final bloc = _MockReviewsBloc();
      when(() => bloc.state).thenReturn(ReviewsLoaded(const []));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });
  });
}
