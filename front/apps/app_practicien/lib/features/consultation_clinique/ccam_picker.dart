import 'package:flutter/material.dart';

class CcamAct {
  final String code;
  final String label;

  const CcamAct({required this.code, required this.label});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CcamAct && other.code == code && other.label == label;

  @override
  int get hashCode => Object.hash(code, label);
}

abstract class GetActsUseCase {
  Future<List<CcamAct>> search(String prefix);
}

class StubGetActsUseCase implements GetActsUseCase {
  static const _db = [
    CcamAct(code: 'HBLD001', label: 'Détartrage sus et sous-gingival'),
    CcamAct(code: 'HBLD002', label: 'Radiographie rétro-alvéolaire'),
    CcamAct(code: 'HBLD003', label: 'Extraction dentaire simple'),
    CcamAct(code: 'HBLD004', label: 'Obturation coronaire composite'),
    CcamAct(code: 'HBLD005', label: 'Scellement sillon carie'),
    CcamAct(code: 'HBLD006', label: 'Désensibilisation dentinaire'),
    CcamAct(code: 'HBLD007', label: 'Traitement endodontique monoradiculé'),
    CcamAct(code: 'HBLD008', label: 'Contention parodontale'),
  ];

  const StubGetActsUseCase();

  @override
  Future<List<CcamAct>> search(String prefix) async {
    final q = prefix.toLowerCase();
    return _db
        .where(
          (a) =>
              a.code.toLowerCase().contains(q) ||
              a.label.toLowerCase().contains(q),
        )
        .take(8)
        .toList();
  }
}

class CcamPicker extends StatefulWidget {
  final GetActsUseCase useCase;
  final void Function(CcamAct act) onActSelected;

  const CcamPicker({
    super.key,
    required this.useCase,
    required this.onActSelected,
  });

  @override
  State<CcamPicker> createState() => _CcamPickerState();
}

class _CcamPickerState extends State<CcamPicker> {
  final _controller = TextEditingController();
  List<CcamAct>? _suggestions;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String value) async {
    if (value.length <= 3) {
      if (_suggestions != null) setState(() => _suggestions = null);
      return;
    }
    final results = await widget.useCase.search(value);
    if (!mounted) return;
    setState(() => _suggestions = results.take(8).toList());
  }

  void _select(CcamAct act) {
    _controller.clear();
    setState(() => _suggestions = null);
    widget.onActSelected(act);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            key: const Key('ccam_search_field'),
            controller: _controller,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Rechercher un acte CCAM',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (suggestions != null)
          suggestions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Aucun acte trouvé',
                      key: const Key('ccam_no_results'),
                    ),
                  ),
                )
              : ListView.builder(
                  key: const Key('ccam_suggestions'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: suggestions.length,
                  itemBuilder: (context, i) => ListTile(
                    key: Key('ccam_act_${suggestions[i].code}'),
                    title: Text(suggestions[i].label),
                    subtitle: Text(suggestions[i].code),
                    onTap: () => _select(suggestions[i]),
                  ),
                ),
      ],
    );
  }
}
