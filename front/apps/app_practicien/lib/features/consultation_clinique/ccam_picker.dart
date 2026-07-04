import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

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
          child: NubiaTextField(
            key: const Key('ccam_search_field'),
            variant: NubiaTextFieldVariant.search,
            controller: _controller,
            onChanged: _onChanged,
            hint: 'Rechercher un acte CCAM',
          ),
        ),
        if (suggestions != null)
          suggestions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Aucun acte trouvé',
                    key: const Key('ccam_no_results'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                )
              : ListView.builder(
                  key: const Key('ccam_suggestions'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: suggestions.length,
                  itemBuilder: (context, i) => ListRow(
                    key: Key('ccam_act_${suggestions[i].code}'),
                    leading: const Icon(Icons.add_circle_outline, size: 22),
                    title: suggestions[i].label,
                    subtitle: suggestions[i].code,
                    onTap: () => _select(suggestions[i]),
                  ),
                ),
      ],
    );
  }
}
