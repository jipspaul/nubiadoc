import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Mention qui engage sur une ligne d'ordonnance : « Substituable » (+
/// générique délivré le cas échéant) ou « Non substituable — MTE ». Texte
/// + couleur (jamais la couleur seule), cohérent avec [StatusPill].
class SubstitutionTags extends StatelessWidget {
  const SubstitutionTags({super.key, required this.item});

  final PrescriptionItem item;

  @override
  Widget build(BuildContext context) {
    if (!item.substitutable) {
      return const Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _Tag(
            label: 'Non substituable — MTE',
            background: NubiaColors.dangerBg,
            foreground: NubiaColors.dangerFg,
            border: NubiaColors.dangerBorder,
          ),
        ],
      );
    }

    final generic = item.dispensedGeneric;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        const _Tag(
          label: 'Substituable',
          background: NubiaColors.brand50,
          foreground: NubiaColors.brand800,
          border: NubiaColors.brand200,
        ),
        if (generic != null && generic.isNotEmpty)
          _Tag(
            label: 'Générique délivré : $generic',
            background: NubiaColors.n100,
            foreground: NubiaColors.n700,
          ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.background,
    required this.foreground,
    this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}
