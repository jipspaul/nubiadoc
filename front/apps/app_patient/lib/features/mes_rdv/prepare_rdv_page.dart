import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'widgets/prepare_rdv_info_card.dart';

// ── Prefs service (mock-able) ────────────────────────────────────────────────

abstract class PrepareRdvPrefsService {
  Future<Set<String>> loadChecked(String rdvId);
  Future<void> saveChecked(String rdvId, Set<String> ids);
}

class InMemoryPrepareRdvPrefsService implements PrepareRdvPrefsService {
  final Map<String, Set<String>> _store = {};

  @override
  Future<Set<String>> loadChecked(String rdvId) async =>
      Set<String>.from(_store[rdvId] ?? <String>{});

  @override
  Future<void> saveChecked(String rdvId, Set<String> ids) async =>
      _store[rdvId] = Set<String>.from(ids);
}

// ── Helpers ──────────────────────────────────────────────────────────────────

String itemIdFromLabel(String label) => label
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

// ── Page ─────────────────────────────────────────────────────────────────────

class PrepareRdvPage extends StatefulWidget {
  const PrepareRdvPage({
    super.key,
    required this.appointmentId,
    this.prefsService,
    this.useCase,
  });

  final String appointmentId;
  final PrepareRdvPrefsService? prefsService;
  final GetAppointmentPreparationUseCase? useCase;

  @override
  State<PrepareRdvPage> createState() => _PrepareRdvPageState();
}

class _PrepareRdvPageState extends State<PrepareRdvPage> {
  late final PrepareRdvPrefsService _prefs;
  late final GetAppointmentPreparationUseCase _useCase;
  bool _loading = true;
  String? _error;
  AppointmentPreparation? _prep;
  Set<String> _checked = const {};

  @override
  void initState() {
    super.initState();
    _prefs = widget.prefsService ?? InMemoryPrepareRdvPrefsService();
    _useCase =
        widget.useCase ?? GetIt.instance<GetAppointmentPreparationUseCase>();
    _load();
  }

  Future<void> _load() async {
    final result = await _useCase(widget.appointmentId);
    final checked = await _prefs.loadChecked(widget.appointmentId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.message;
      }),
      (prep) => setState(() {
        _loading = false;
        _error = null;
        _prep = prep;
        _checked = checked;
      }),
    );
  }

  Future<void> _toggle(String itemId) async {
    final next = Set<String>.from(_checked);
    if (next.contains(itemId)) {
      next.remove(itemId);
    } else {
      next.add(itemId);
    }
    await _prefs.saveChecked(widget.appointmentId, next);
    setState(() => _checked = next);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Préparer mon RDV')),
        body: const Center(
          key: Key('prepare_rdv_loading'),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Préparer mon RDV')),
        body: Center(
          key: const Key('prepare_rdv_error'),
          child: Text(_error!),
        ),
      );
    }
    final prep = _prep!;
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer mon RDV')),
      body: ListView(
        key: const Key('prepare_rdv_list'),
        padding: const EdgeInsets.all(16),
        children: [
          PrepareRdvInfoCard(preparation: prep),
          const SizedBox(height: 16),
          ...prep.items.map((item) {
            final itemId = itemIdFromLabel(item.label);
            final isChecked = _checked.contains(itemId);
            return Card(
              key: Key('item_$itemId'),
              child: ListTile(
                leading: Icon(
                  isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                ),
                title: Text(item.label),
                onTap: () => _toggle(itemId),
              ),
            );
          }),
        ],
      ),
    );
  }
}
