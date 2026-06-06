import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nubia_patient/domain/entities/review.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// Displays a single published [Review]: stars, author, date, and comment.
class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final formatted = DateFormat('d MMM yyyy', 'fr').format(review.createdAt);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StarRating(rating: review.rating),
                const Spacer(),
                Text(
                  formatted,
                  style: textTheme.bodySmall
                      ?.copyWith(color: tokens.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              review.authorName,
              style: textTheme.labelMedium,
            ),
            if (review.comment != null && review.comment!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                review.comment!,
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
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
    final color = Theme.of(context).extension<NubiaTokens>()!.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < rating ? Icons.star : Icons.star_border,
          size: 18,
          color: color,
        ),
      ),
    );
  }
}
