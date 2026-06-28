import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'reviews_bloc.dart';
import 'reviews_event.dart';
import 'reviews_state.dart';

/// Page affichant les avis d'un prestataire et permettant d'en soumettre un.
///
/// Doit être placée dans un [BlocProvider<ReviewsBloc>].
/// Le caller ajoute [ReviewsLoadRequested] via le callback `create` du BlocProvider.
class ReviewsPage extends StatelessWidget {
  const ReviewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReviewsBloc, ReviewsState>(
      builder: (context, state) {
        if (state is ReviewsInitial || state is ReviewsLoading) {
          return const Center(
            key: Key('reviews_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is ReviewsError) {
          return NubiaErrorWidget(
            key: const Key('reviews_error'),
            message: state.message,
            onRetry: () =>
                context.read<ReviewsBloc>().add(const ReviewsLoadRequested('')),
          );
        }
        if (state is ReviewSubmitting) {
          return const Center(
            key: Key('reviews_submitting'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is ReviewSubmitSuccess) {
          return const Center(
            key: Key('reviews_submit_success'),
            child: Text('Avis soumis avec succès.'),
          );
        }
        if (state is ReviewSubmitFailure) {
          return Center(
            key: const Key('reviews_submit_failure'),
            child: Text(state.message),
          );
        }
        if (state is ReviewsLoaded) {
          return _ReviewsContent(reviews: state.reviews);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _ReviewsContent extends StatelessWidget {
  const _ReviewsContent({required this.reviews});

  final List<Review> reviews;

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return const NubiaEmptyState(
        key: Key('reviews_empty'),
        icon: Icons.rate_review_outlined,
        title: 'Aucun avis pour ce prestataire.',
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        final bloc = context.read<ReviewsBloc>();
        bloc.add(ReviewsLoadRequested(reviews.first.providerId));
        await bloc.stream.firstWhere(
          (s) => s is ReviewsLoaded || s is ReviewsError,
          orElse: () => const ReviewsLoading(),
        );
      },
      child: ListView.separated(
        key: const Key('reviews_list'),
        padding: const EdgeInsets.all(16),
        itemCount: reviews.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, i) => _ReviewCard(review: reviews[i]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                review.authorName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              _StarRating(rating: review.rating),
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(review.comment!),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StarRating extends StatelessWidget {
  const _StarRating({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < rating ? Icons.star : Icons.star_border,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
