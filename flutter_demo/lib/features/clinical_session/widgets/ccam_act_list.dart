import 'package:flutter/material.dart';

import '../models/ccam_act.dart';

/// Liste des actes CCAM ajoutés pendant la séance.
class CcamActList extends StatelessWidget {
  const CcamActList({
    super.key,
    required this.acts,
    required this.onRemove,
    this.enabled = true,
  });

  final List<CcamAct> acts;
  final void Function(String actId) onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (acts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Aucun acte ajouté',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: acts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => _CcamActTile(
        act: acts[i],
        onRemove: enabled ? () => onRemove(acts[i].id) : null,
      ),
    );
  }
}

class _CcamActTile extends StatelessWidget {
  const _CcamActTile({required this.act, this.onRemove});

  final CcamAct act;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final amountLabel = act.amountCents != null
        ? '${(act.amountCents! / 100).toStringAsFixed(2)} €'
        : null;

    return ListTile(
      key: Key('act_tile_${act.id}'),
      dense: true,
      title: Text(act.label, style: textTheme.bodyMedium),
      subtitle: Text(
        [act.ccamCode, if (act.tooth != null) 'Dent ${act.tooth}'].join(' · '),
        style: textTheme.labelSmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (amountLabel != null)
            Text(amountLabel, style: textTheme.labelLarge),
          if (onRemove != null) ...[
            const SizedBox(width: 8),
            IconButton(
              key: Key('btn_remove_act_${act.id}'),
              icon: Icon(
                Icons.remove_circle_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              onPressed: onRemove,
              tooltip: 'Retirer',
              iconSize: 20,
            ),
          ],
        ],
      ),
    );
  }
}
