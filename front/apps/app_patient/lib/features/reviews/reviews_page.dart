import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'reviews_bloc.dart';
import 'reviews_event.dart';
import 'reviews_state.dart';

/// Page affichant les avis d'un prestataire, ou le formulaire de saisie d'un
/// nouvel avis quand [appointmentId] est fourni (arrivée via le deep-link de
/// la notification `review_request`, #6624).
///
/// Doit être placée dans un [BlocProvider<ReviewsBloc>].
/// Le caller ajoute [ReviewsLoadRequested] via le callback `create` du
/// BlocProvider (uniquement en mode liste — pas d'appel réseau nécessaire
/// pour afficher un formulaire vierge).
class ReviewsPage extends StatelessWidget {
  const ReviewsPage({super.key, this.appointmentId});

  final String? appointmentId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReviewsBloc, ReviewsState>(
      builder: (context, state) {
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
        if (appointmentId != null) {
          return _ReviewSubmitForm(appointmentId: appointmentId!);
        }
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
            onRetry: () => context
                .read<ReviewsBloc>()
                .add(ReviewsLoadRequested(state.providerId)),
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

/// Formulaire de saisie d'un avis (note 1-5 + commentaire optionnel) pour un
/// rendez-vous donné — appelle `POST /v1/reviews` via [ReviewSubmitRequested].
class _ReviewSubmitForm extends StatefulWidget {
  const _ReviewSubmitForm({required this.appointmentId});

  final String appointmentId;

  @override
  State<_ReviewSubmitForm> createState() => _ReviewSubmitFormState();
}

class _ReviewSubmitFormState extends State<_ReviewSubmitForm> {
  final _commentController = TextEditingController();
  int _rating = 0;

  // Généré une seule fois par formulaire : un nouveau tap sur "Envoyer"
  // (ex. après échec réseau) doit rejouer la même clé pour rester idempotent.
  late final String _idempotencyKey =
      '${widget.appointmentId}-review-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('reviews_submit_form'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Comment s'est passé votre rendez-vous ?",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final value = i + 1;
              return IconButton(
                key: Key('reviews_submit_star_$value'),
                iconSize: 32,
                icon: Icon(
                  value <= _rating ? Icons.star : Icons.star_border,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () => setState(() => _rating = value),
              );
            }),
          ),
          const SizedBox(height: 16),
          NubiaTextField(
            key: const Key('reviews_submit_comment'),
            controller: _commentController,
            label: 'Commentaire (optionnel)',
            variant: NubiaTextFieldVariant.multiline,
          ),
          const SizedBox(height: 20),
          NubiaButton(
            key: const Key('reviews_submit_button'),
            label: 'Envoyer mon avis',
            onPressed: _rating == 0
                ? null
                : () => context.read<ReviewsBloc>().add(
                      ReviewSubmitRequested(
                        appointmentId: widget.appointmentId,
                        rating: _rating,
                        comment: _commentController.text.trim().isEmpty
                            ? null
                            : _commentController.text.trim(),
                        idempotencyKey: _idempotencyKey,
                      ),
                    ),
          ),
        ],
      ),
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
