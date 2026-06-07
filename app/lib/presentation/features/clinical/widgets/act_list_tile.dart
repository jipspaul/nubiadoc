import 'package:flutter/material.dart';
import 'package:nubia_patient/domain/entities/clinical_session.dart';

/// A dismissible list tile representing a single CCAM act.
///
/// Shows code, label, tooth (optional) and amount. Fires [onRemove] when
/// the practitioner dismisses via swipe-to-delete.
class ActListTile extends StatelessWidget {
  const ActListTile({
    super.key,
    required this.act,
    required this.onRemove,
  });

  final ClinicalAct act;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey(act.id),
      direction: DismissDirection.endToStart,
      background: _DismissBackground(colorScheme: colorScheme),
      onDismissed: (_) => onRemove(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(act.label, style: textTheme.bodyMedium),
        subtitle: Text(
          act.ccamCode + (act.tooth != null ? ' · dent ${act.tooth}' : ''),
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: act.amountCents != null
            ? Text(
                '${(act.amountCents! / 100).toStringAsFixed(2)} €',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DismissBackground extends StatelessWidget {
  const _DismissBackground({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: colorScheme.errorContainer,
      child: Icon(Icons.delete_outline, color: colorScheme.onErrorContainer),
    );
  }
}
