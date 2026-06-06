import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/entities/review.dart';
import 'package:nubia_patient/presentation/features/reviews/bloc/reviews_bloc.dart';
import 'package:nubia_patient/presentation/features/reviews/widgets/review_card.dart';
import 'package:nubia_patient/presentation/features/reviews/widgets/review_submit_form.dart';

/// Reviews screen for a given provider.
///
/// Shows published reviews list and a form for submitting a new review
/// (requires a past/honored appointment). [providerId] identifies the
/// practitioner; [honoredAppointments] are the ones eligible for review.
class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({
    super.key,
    required this.providerId,
    required this.honoredAppointments,
  });

  final String providerId;
  final List<Appointment> honoredAppointments;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<ReviewsBloc>()..add(ReviewsLoadRequested(providerId)),
      child: _ReviewsBody(honoredAppointments: honoredAppointments),
    );
  }
}

// ---------------------------------------------------------------------------

class _ReviewsBody extends StatelessWidget {
  const _ReviewsBody({required this.honoredAppointments});

  final List<Appointment> honoredAppointments;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Avis')),
      body: BlocConsumer<ReviewsBloc, ReviewsState>(
        listener: (context, state) {
          if (state is ReviewSubmitSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Avis envoyé, en cours de modération.')),
            );
          } else if (state is ReviewSubmitFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          if (state is ReviewsInitial || state is ReviewsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ReviewsError) {
            return Center(child: Text(state.message));
          }

          final reviews =
              state is ReviewsLoaded ? state.reviews : <Review>[];
          final isSubmitting = state is ReviewSubmitting;

          return _ReviewsContent(
            reviews: reviews,
            honoredAppointments: honoredAppointments,
            isSubmitting: isSubmitting,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ReviewsContent extends StatelessWidget {
  const _ReviewsContent({
    required this.reviews,
    required this.honoredAppointments,
    required this.isSubmitting,
  });

  final List<Review> reviews;
  final List<Appointment> honoredAppointments;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      children: [
        if (honoredAppointments.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Laisser un avis', style: textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ReviewSubmitForm(
              honoredAppointments: honoredAppointments,
              isSubmitting: isSubmitting,
              onSubmit: (appointmentId, rating, comment) {
                context.read<ReviewsBloc>().add(
                      ReviewSubmitRequested(
                        appointmentId: appointmentId,
                        rating: rating,
                        comment: comment,
                        idempotencyKey: _generateIdempotencyKey(),
                      ),
                    );
              },
            ),
          ),
          const Divider(height: 32),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Avis publiés', style: textTheme.titleMedium),
        ),
        if (reviews.isEmpty)
          const _EmptyReviews()
        else
          ...reviews.map((r) => ReviewCard(review: r)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Helpers

String _generateIdempotencyKey() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ---------------------------------------------------------------------------

class _EmptyReviews extends StatelessWidget {
  const _EmptyReviews();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.rate_review_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Aucun avis pour le moment.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
