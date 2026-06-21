import 'package:flutter/material.dart';

// ── Data models ──────────────────────────────────────────────────────────────

class BringItem {
  const BringItem({required this.id, required this.label});
  final String id;
  final String label;
}

class AppointmentPreparation {
  const AppointmentPreparation({required this.address, required this.items});
  final String address;
  final List<BringItem> items;
}

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

// ── Stub (simulates GET /v1/appointments/:id/preparation) ────────────────────

const _kDefaultItems = [
  BringItem(id: 'carte_vitale', label: 'Carte Vitale'),
  BringItem(id: 'carte_mutuelle', label: 'Carte mutuelle'),
  BringItem(id: 'ordonnance', label: 'Ordonnance'),
];

AppointmentPreparation _stubPreparation(String id) =>
    const AppointmentPreparation(
      address: '12 rue de la Paix, 75001 Paris',
      items: _kDefaultItems,
    );

// ── Page ─────────────────────────────────────────────────────────────────────

class PrepareRdvPage extends StatefulWidget {
  const PrepareRdvPage({
    super.key,
    required this.appointmentId,
    this.prefsService,
  });

  final String appointmentId;
  final PrepareRdvPrefsService? prefsService;

  @override
  State<PrepareRdvPage> createState() => _PrepareRdvPageState();
}

class _PrepareRdvPageState extends State<PrepareRdvPage> {
  late final PrepareRdvPrefsService _prefs;
  bool _loading = true;
  AppointmentPreparation? _prep;
  Set<String> _checked = const {};

  @override
  void initState() {
    super.initState();
    _prefs = widget.prefsService ?? InMemoryPrepareRdvPrefsService();
    _load();
  }

  Future<void> _load() async {
    final prep = _stubPreparation(widget.appointmentId);
    final checked = await _prefs.loadChecked(widget.appointmentId);
    if (mounted) {
      setState(() {
        _loading = false;
        _prep = prep;
        _checked = checked;
      });
    }
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
    final prep = _prep!;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          prep.address,
          key: const Key('prepare_rdv_address'),
        ),
      ),
      body: ListView(
        key: const Key('prepare_rdv_list'),
        padding: const EdgeInsets.all(16),
        children: prep.items.map((item) {
          final isChecked = _checked.contains(item.id);
          return Card(
            key: Key('item_${item.id}'),
            child: ListTile(
              leading: Icon(
                isChecked ? Icons.check_box : Icons.check_box_outline_blank,
              ),
              title: Text(item.label),
              onTap: () => _toggle(item.id),
            ),
          );
        }).toList(),
      ),
    );
  }
}
