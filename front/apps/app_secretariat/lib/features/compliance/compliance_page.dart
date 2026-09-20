import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/back_or_home_leading.dart';
import 'compliance_bloc.dart';
import 'compliance_event.dart';
import 'compliance_state.dart';
import 'widgets/compliance_item_row.dart';

const List<String> _kComplianceKinds = [
  'training',
  'equipment_check',
  'register',
  'other',
];

String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Écran « Conformité » (#7169) : échéancier ARS/DMSM du cabinet (à venir /
/// échu / fait, par membre et par équipement), création d'items, pièce
/// justificative.
class CompliancePage extends StatelessWidget {
  const CompliancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<ComplianceBloc>()
        ..add(const ComplianceLoadRequested()),
      child: const _ComplianceView(),
    );
  }
}

class _ComplianceView extends StatefulWidget {
  const _ComplianceView();

  @override
  State<_ComplianceView> createState() => _ComplianceViewState();
}

class _ComplianceViewState extends State<_ComplianceView> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: backOrHomeLeading(context),
        title: const Text('Conformité'),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('compliance_create_fab'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => BlocProvider.value(
            value: context.read<ComplianceBloc>(),
            child: const _CreateComplianceItemDialog(),
          ),
        ),
        child: const Icon(Icons.add),
      ),
      body: BlocListener<ComplianceBloc, ComplianceState>(
        listenWhen: (_, current) =>
            current is ComplianceLoaded && current.actionError != null,
        listener: (context, state) {
          if (state is ComplianceLoaded && state.actionError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.actionError!)),
            );
          }
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const Key('compliance_filter_pending'),
                    label: const Text('À venir / échu'),
                    selected: !_showDone,
                    onSelected: (_) => setState(() => _showDone = false),
                  ),
                  ChoiceChip(
                    key: const Key('compliance_filter_done'),
                    label: const Text('Clôturés'),
                    selected: _showDone,
                    onSelected: (_) => setState(() => _showDone = true),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<ComplianceBloc, ComplianceState>(
                builder: (context, state) {
                  return switch (state) {
                    ComplianceInitial() || ComplianceLoading() => const Center(
                        key: Key('compliance_page_loading'),
                        child: CircularProgressIndicator(),
                      ),
                    ComplianceError(:final message) => NubiaErrorWidget(
                        key: const Key('compliance_page_error'),
                        message: message,
                        onRetry: () => context
                            .read<ComplianceBloc>()
                            .add(const ComplianceLoadRequested()),
                      ),
                    ComplianceLoaded() => _ComplianceList(
                        items: _showDone ? state.done : state.pending,
                      ),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComplianceList extends StatelessWidget {
  const _ComplianceList({required this.items});

  final List<ComplianceItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const NubiaEmptyState(
        key: Key('compliance_page_empty'),
        icon: Icons.fact_check_outlined,
        title: 'Aucun item',
        subtitle: 'Aucun item ne correspond à ce filtre.',
      );
    }
    return ListView.builder(
      key: const Key('compliance_page_list'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, i) => ComplianceItemRow(
        item: items[i],
        onComplete: () => context
            .read<ComplianceBloc>()
            .add(ComplianceCompleteRequested(items[i].id)),
        onAttachEvidence: () => showDialog<void>(
          context: context,
          builder: (_) => BlocProvider.value(
            value: context.read<ComplianceBloc>(),
            child: _AttachEvidenceDialog(itemId: items[i].id),
          ),
        ),
      ),
    );
  }
}

class _AttachEvidenceDialog extends StatefulWidget {
  const _AttachEvidenceDialog({required this.itemId});

  final String itemId;

  @override
  State<_AttachEvidenceDialog> createState() => _AttachEvidenceDialogState();
}

class _AttachEvidenceDialogState extends State<_AttachEvidenceDialog> {
  final _documentIdCtrl = TextEditingController();

  @override
  void dispose() {
    _documentIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _documentIdCtrl.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Joindre un justificatif'),
      content: TextField(
        key: const Key('compliance_evidence_document_id_field'),
        controller: _documentIdCtrl,
        decoration: const InputDecoration(
          labelText: 'Identifiant du document (coffre-fort)',
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('compliance_evidence_confirm'),
          onPressed: canConfirm
              ? () {
                  context.read<ComplianceBloc>().add(
                        ComplianceEvidenceAttachRequested(
                          itemId: widget.itemId,
                          evidenceDocumentId: _documentIdCtrl.text.trim(),
                        ),
                      );
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Joindre'),
        ),
      ],
    );
  }
}

/// Dialogue de création d'un item (#7169) : type + libellé + membre
/// concerné optionnel + équipement optionnel + échéance + récurrence
/// optionnelle.
class _CreateComplianceItemDialog extends StatefulWidget {
  const _CreateComplianceItemDialog();

  @override
  State<_CreateComplianceItemDialog> createState() =>
      _CreateComplianceItemDialogState();
}

class _CreateComplianceItemDialogState
    extends State<_CreateComplianceItemDialog> {
  final _labelCtrl = TextEditingController();
  final _equipmentCtrl = TextEditingController();
  final _recurrenceCtrl = TextEditingController();
  String _kind = _kComplianceKinds.first;
  DateTime? _dueDate;
  Member? _subject;
  List<Member> _members = const [];
  bool _loadingMembers = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final result = await GetIt.instance<ListMembersUseCase>()();
    if (!mounted) return;
    result.fold(
      (_) => setState(() => _loadingMembers = false),
      (members) => setState(() {
        _members = members;
        _loadingMembers = false;
      }),
    );
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _equipmentCtrl.dispose();
    _recurrenceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _labelCtrl.text.trim().isNotEmpty && _dueDate != null;
    return AlertDialog(
      title: const Text('Nouvel item de conformité'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Type'),
              child: DropdownButton<String>(
                key: const Key('compliance_kind_dropdown'),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                value: _kind,
                items: [
                  for (final kind in _kComplianceKinds)
                    DropdownMenuItem<String>(
                      value: kind,
                      child: Text(complianceKindLabel(kind)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _kind = value ?? _kind),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('compliance_label_field'),
              controller: _labelCtrl,
              decoration: const InputDecoration(labelText: 'Libellé *'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_loadingMembers)
              const LinearProgressIndicator(
                key: Key('compliance_members_loading'),
              )
            else
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Membre concerné'),
                child: DropdownButton<Member?>(
                  key: const Key('compliance_subject_dropdown'),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  value: _subject,
                  hint: const Text('Aucun (optionnel)'),
                  items: [
                    const DropdownMenuItem<Member?>(
                      value: null,
                      child: Text('Aucun (optionnel)'),
                    ),
                    for (final member in _members)
                      DropdownMenuItem<Member?>(
                        value: member,
                        child: Text(member.fullName),
                      ),
                  ],
                  onChanged: (m) => setState(() => _subject = m),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('compliance_equipment_field'),
              controller: _equipmentCtrl,
              decoration: const InputDecoration(
                labelText: 'Équipement (optionnel)',
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              key: const Key('compliance_due_date_picker'),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? now,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 10),
                );
                if (picked != null) setState(() => _dueDate = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Échéance *'),
                child: Text(
                  _dueDate == null ? 'Choisir une date' : _isoDate(_dueDate!),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('compliance_recurrence_field'),
              controller: _recurrenceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Récurrence en mois (optionnel)',
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
          key: const Key('compliance_create_confirm'),
          onPressed: canCreate
              ? () {
                  final recurrence = int.tryParse(_recurrenceCtrl.text.trim());
                  context.read<ComplianceBloc>().add(
                        ComplianceCreateRequested(
                          kind: _kind,
                          label: _labelCtrl.text.trim(),
                          subjectUserId: _subject?.id,
                          equipmentLabel: _equipmentCtrl.text.trim().isEmpty
                              ? null
                              : _equipmentCtrl.text.trim(),
                          dueDate: _isoDate(_dueDate!),
                          recurrenceMonths: recurrence,
                        ),
                      );
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
