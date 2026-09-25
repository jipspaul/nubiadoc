import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/back_or_home_leading.dart';
import '../../session/pro_auth_cubit.dart';
import 'mes_conges_bloc.dart';
import 'mes_conges_event.dart';
import 'mes_conges_state.dart';
import 'widgets/leave_request_row.dart';

const _kKindOptions = [
  'paid_leave',
  'unpaid_leave',
  'sick_leave',
  'other',
];

/// Route « Mes congés » (#7143/#7144) : résout l'utilisateur courant et
/// instancie [MesCongesBloc] via GetIt — voir [MesCongesBody] pour l'UI,
/// testable indépendamment sans session/GetIt (même découpage que
/// `AuditLogPage`/`AuditLogBody`).
class MesCongesPage extends StatelessWidget {
  const MesCongesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final myUserId = switch (context.watch<ProAuthCubit>().state) {
      AuthAuthenticated(:final session) => session.userId,
      _ => null,
    };
    return BlocProvider(
      create: (_) => GetIt.instance<MesCongesBloc>()
        ..add(MesCongesLoadRequested(userId: myUserId)),
      child: const MesCongesBody(),
    );
  }
}

/// Écran « Mes congés » (#7143/#7144) : demande de congé depuis le
/// téléphone, suivi du statut de mes demandes, annulation tant que
/// réversible.
class MesCongesBody extends StatelessWidget {
  const MesCongesBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('mes_conges_scaffold'),
      appBar: AppBar(
        leading: backOrHomeLeading(context),
        title: const Text('Mes congés'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('mes_conges_create_fab'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => BlocProvider.value(
            value: context.read<MesCongesBloc>(),
            child: const _CreateLeaveRequestDialog(),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Demander un congé'),
      ),
      body: BlocListener<MesCongesBloc, MesCongesState>(
        listenWhen: (_, current) =>
            current is MesCongesLoaded && current.actionError != null,
        listener: (context, state) {
          if (state is MesCongesLoaded && state.actionError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.actionError!)),
            );
          }
        },
        child: BlocBuilder<MesCongesBloc, MesCongesState>(
          builder: (context, state) {
            return switch (state) {
              MesCongesLoading() => const Center(
                  key: Key('mes_conges_loading'),
                  child: CircularProgressIndicator(),
                ),
              MesCongesError(:final message) => NubiaErrorWidget(
                  key: const Key('mes_conges_error'),
                  message: message,
                  onRetry: () => context
                      .read<MesCongesBloc>()
                      .add(const MesCongesLoadRequested()),
                ),
              MesCongesLoaded(:final requests) when requests.isEmpty =>
                const NubiaEmptyState(
                  key: Key('mes_conges_empty'),
                  icon: Icons.beach_access_outlined,
                  title: 'Aucune demande de congé',
                  subtitle: 'Utilisez le bouton + pour faire une demande.',
                ),
              MesCongesLoaded(:final requests) => ListView.builder(
                  key: const Key('mes_conges_list'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: requests.length,
                  itemBuilder: (_, i) => LeaveRequestRow(
                    leaveRequest: requests[i],
                    onCancel: () => context
                        .read<MesCongesBloc>()
                        .add(MesCongesCancelRequested(requests[i].id)),
                  ),
                ),
            };
          },
        ),
      ),
    );
  }
}

class _CreateLeaveRequestDialog extends StatefulWidget {
  const _CreateLeaveRequestDialog();

  @override
  State<_CreateLeaveRequestDialog> createState() =>
      _CreateLeaveRequestDialogState();
}

class _CreateLeaveRequestDialogState extends State<_CreateLeaveRequestDialog> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _kind = _kKindOptions.first;

  bool get _canCreate =>
      _startDate != null &&
      _endDate != null &&
      !_endDate!.isBefore(_startDate!);

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startDate : _endDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => isStart ? _startDate = picked : _endDate = picked);
    }
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Choisir une date';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle demande de congé'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const Key('leave_start_date_picker'),
              onTap: () => _pickDate(isStart: true),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Du'),
                child: Text(_dateLabel(_startDate)),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              key: const Key('leave_end_date_picker'),
              onTap: () => _pickDate(isStart: false),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Au'),
                child: Text(_dateLabel(_endDate)),
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Type'),
              child: DropdownButton<String>(
                key: const Key('leave_kind_dropdown'),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                value: _kind,
                items: [
                  for (final kind in _kKindOptions)
                    DropdownMenuItem<String>(
                      value: kind,
                      child: Text(kindLabel(kind)),
                    ),
                ],
                onChanged: (value) => setState(() => _kind = value ?? _kind),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('leave_create_confirm'),
          onPressed: _canCreate
              ? () {
                  final start = _startDate!;
                  final end = _endDate!;
                  context.read<MesCongesBloc>().add(MesCongesCreateRequested(
                        startsAt:
                            DateTime.utc(start.year, start.month, start.day)
                                .toIso8601String(),
                        endsAt: DateTime.utc(
                                end.year, end.month, end.day, 23, 59, 59)
                            .toIso8601String(),
                        kind: _kind,
                      ));
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Envoyer la demande'),
        ),
      ],
    );
  }
}
