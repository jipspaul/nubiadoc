import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'consultation_format_utils.dart' show formatShortDate;

/// Encart « Dernières séances » (#4937) — colonne de contexte gauche (≥ 1280
/// px) de la consultation au fauteuil. Historique récent du patient de la
/// séance en cours, cloisonné via `listSessions(patientId: ...)`.
class RecentSessionsBox extends StatefulWidget {
  const RecentSessionsBox({
    super.key,
    required this.patientId,
    this.excludeSessionId,
  });

  final String patientId;

  /// Séance en cours, exclue de l'historique (elle n'est pas "passée").
  final String? excludeSessionId;

  @override
  State<RecentSessionsBox> createState() => _RecentSessionsBoxState();
}

class _RecentSessionsBoxState extends State<RecentSessionsBox> {
  late final Future<List<ClinicalSession>> _future = _load();

  Future<List<ClinicalSession>> _load() async {
    final result = await GetIt.instance<ListClinicalSessionsUseCase>()
        .call(patientId: widget.patientId);
    return result.fold(
      (_) => const <ClinicalSession>[],
      (sessions) => sessions
          .where((s) => s.id != widget.excludeSessionId)
          .take(5)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClinicalSession>>(
      future: _future,
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const <ClinicalSession>[];
        if (snapshot.connectionState != ConnectionState.done ||
            sessions.isEmpty) {
          return const SizedBox.shrink();
        }
        return NubiaCard(
          key: const Key('recent_sessions_box'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Dernières séances',
                      style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < sessions.length; i++)
                _RecentSessionRow(
                  key: Key('recent_session_${sessions[i].id}'),
                  session: sessions[i],
                  showDivider: i < sessions.length - 1,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RecentSessionRow extends StatelessWidget {
  const _RecentSessionRow({
    super.key,
    required this.session,
    required this.showDivider,
  });

  final ClinicalSession session;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final act = session.acts.isEmpty ? null : session.acts.first;
    final tooth = act?.tooth?.trim();
    final practitioner = session.practitionerName?.trim();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: NubiaColors.n100)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              session.startedAt != null
                  ? formatShortDate(session.startedAt!)
                  : '',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (act != null)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: act.label,
                          style: textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (tooth != null && tooth.isNotEmpty)
                          TextSpan(
                            text: ' · $tooth',
                            style: textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                if (practitioner != null && practitioner.isNotEmpty)
                  Text(
                    practitioner,
                    style:
                        textTheme.bodySmall?.copyWith(color: onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
