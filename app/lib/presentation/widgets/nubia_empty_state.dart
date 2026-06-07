// lib/presentation/widgets/nubia_empty_state.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Widget d'état vide transverse : illustration SVG + message + CTA optionnel.
///
/// - [svgAsset] : chemin de l'asset SVG (ex. `assets/images/empty_state.svg`).
///   Si null, l'illustration est omise.
/// - [message] : texte principal affiché sous l'illustration.
/// - [actionLabel] : libellé du bouton CTA. Requis si [onAction] est non null.
/// - [onAction] : callback du CTA. Quand null, le bouton n'est pas affiché.
class NubiaEmptyState extends StatelessWidget {
  const NubiaEmptyState({
    super.key,
    this.svgAsset,
    required this.message,
    this.actionLabel,
    this.onAction,
  }) : assert(
          onAction == null || actionLabel != null,
          'actionLabel doit être fourni quand onAction est non null',
        );

  final String? svgAsset;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (svgAsset != null)
              SvgPicture.asset(
                svgAsset!,
                width: 160,
                height: 160,
                semanticsLabel: message,
              ),
            if (svgAsset != null) const SizedBox(height: 24),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            if (onAction != null) const SizedBox(height: 16),
            if (onAction != null)
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
