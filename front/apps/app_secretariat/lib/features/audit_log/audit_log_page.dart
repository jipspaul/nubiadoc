import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'audit_log_bloc.dart';
import 'audit_log_event.dart';
import 'audit_log_state.dart';

/// Page complète (route dédiée) — `Scaffold` + `AppBar` autour de
/// [AuditLogBody], même découpage que `CabinetStatsPage`.
class AuditLogPage extends StatelessWidget {
  const AuditLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('audit_log_scaffold'),
      appBar: AppBar(title: const Text("Journal d'accès")),
      body: const AuditLogBody(),
    );
  }
}

const double _kContentMaxWidth = 900;

String _formatOccurredAt(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _formatDateButton(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Corps réutilisable du journal d'accès (#4155) — embarquable dans un onglet
/// `ProShell` ou une page dédiée. Filtres date/entité, réservé admin/manager
/// (403 → [AuditLogForbidden]).
class AuditLogBody extends StatefulWidget {
  const AuditLogBody({super.key});

  @override
  State<AuditLogBody> createState() => _AuditLogBodyState();
}

class _AuditLogBodyState extends State<AuditLogBody> {
  DateTime? _from;
  DateTime? _to;
  final _entityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<AuditLogBloc>().add(const AuditLogLoadRequested());
  }

  @override
  void dispose() {
    _entityController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final entity = _entityController.text.trim();
    context.read<AuditLogBloc>().add(AuditLogLoadRequested(
          from: _from,
          to: _to,
          entity: entity.isEmpty ? null : entity,
        ));
  }

  void _resetFilters() {
    setState(() {
      _from = null;
      _to = null;
      _entityController.clear();
    });
    context.read<AuditLogBloc>().add(const AuditLogLoadRequested());
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => isFrom ? _from = picked : _to = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isForbidden =
        context.watch<AuditLogBloc>().state is AuditLogForbidden;
    return Column(
      children: [
        _AuditLogFilterBar(
          from: _from,
          to: _to,
          entityController: _entityController,
          onPickFrom: () => _pickDate(isFrom: true),
          onPickTo: () => _pickDate(isFrom: false),
          onApply: isForbidden ? null : _applyFilters,
          onReset: isForbidden ? null : _resetFilters,
        ),
        Expanded(
          child: BlocBuilder<AuditLogBloc, AuditLogState>(
            builder: (context, state) {
              switch (state) {
                case AuditLogLoading():
                  return const Center(
                    key: Key('audit_log_loading'),
                    child: CircularProgressIndicator(),
                  );
                case AuditLogForbidden():
                  return const NubiaEmptyState(
                    key: Key('audit_log_forbidden'),
                    icon: Icons.lock_outline,
                    title: 'Accès réservé aux administrateurs',
                    subtitle:
                        "Le journal d'accès n'est visible que par les rôles admin/manager du cabinet.",
                  );
                case AuditLogError(:final message):
                  return NubiaErrorWidget(
                    key: const Key('audit_log_error'),
                    message: message,
                    onRetry: () => context
                        .read<AuditLogBloc>()
                        .add(const AuditLogLoadRequested()),
                  );
                case AuditLogLoaded(:final entries):
                  return _AuditLogListView(entries: entries);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _AuditLogFilterBar extends StatelessWidget {
  const _AuditLogFilterBar({
    required this.from,
    required this.to,
    required this.entityController,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onApply,
    required this.onReset,
  });

  final DateTime? from;
  final DateTime? to;
  final TextEditingController entityController;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback? onApply;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('audit_log_from_filter'),
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(from == null ? 'Depuis' : _formatDateButton(from!)),
                onPressed: onPickFrom,
              ),
              OutlinedButton.icon(
                key: const Key('audit_log_to_filter'),
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(to == null ? "Jusqu'au" : _formatDateButton(to!)),
                onPressed: onPickTo,
              ),
              SizedBox(
                width: 220,
                child: NubiaTextField(
                  key: const Key('audit_log_entity_filter'),
                  controller: entityController,
                  label: 'Entité',
                  hint: 'ex. patient, quote…',
                ),
              ),
              FilledButton(
                key: const Key('audit_log_apply_filters'),
                onPressed: onApply,
                child: const Text('Filtrer'),
              ),
              TextButton(
                key: const Key('audit_log_reset_filters'),
                onPressed: onReset,
                child: const Text('Réinitialiser'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditLogListView extends StatelessWidget {
  const _AuditLogListView({required this.entries});

  final List<AuditLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const NubiaEmptyState(
        key: Key('audit_log_empty'),
        icon: Icons.history_outlined,
        title: 'Aucun accès sur la période',
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return ListView.builder(
      key: const Key('audit_log_loaded'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NubiaCard(
                key: Key('audit_log_entry_${entry.id}'),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.action} · ${entry.entity}',
                            style: textTheme.titleSmall,
                          ),
                          if (entry.actorRole != null)
                            Text(
                              'par ${entry.actorRole}',
                              style: textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    Text(
                      _formatOccurredAt(entry.occurredAt),
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
