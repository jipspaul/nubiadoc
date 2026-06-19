import 'package:flutter/material.dart';

/// A2UI catalog primitives not yet covered by the historical Nubia widget set.
///
/// These are intentionally simple, theme-driven stubs so that the A2UI catalog
/// (`Tabs`, `CheckBox`, `DateTimeInput`, `ChoicePicker`, `Slider`) has a 1:1
/// native mapping. They will be refined to full design-system fidelity later.

/// Tabs — a labelled tab bar over a set of child views.
class NubiaTabs extends StatelessWidget {
  const NubiaTabs({super.key, required this.tabs, required this.views})
      : assert(tabs.length == views.length, 'tabs and views must align');

  final List<String> tabs;
  final List<Widget> views;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(tabs: [for (final t in tabs) Tab(text: t)]),
          Flexible(child: TabBarView(children: views)),
        ],
      ),
    );
  }
}

/// CheckBox — a labelled boolean input.
class NubiaCheckbox extends StatelessWidget {
  const NubiaCheckbox({
    super.key,
    required this.value,
    this.label,
    this.onChanged,
  });

  final bool value;
  final String? label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
          ),
          if (label != null) Flexible(child: Text(label!)),
        ],
      ),
    );
  }
}

/// DateTimeInput — opens a native date (and optionally time) picker.
class NubiaDateTimeInput extends StatelessWidget {
  const NubiaDateTimeInput({
    super.key,
    this.value,
    this.label,
    this.withTime = false,
    this.onChanged,
  });

  final DateTime? value;
  final String? label;
  final bool withTime;
  final ValueChanged<DateTime>? onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime(2020);
    final date = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime(2026, 6, 14),
      firstDate: now,
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    onChanged?.call(date);
  }

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? (label ?? 'Choisir une date')
        : '${value!.day}/${value!.month}/${value!.year}';
    return OutlinedButton.icon(
      onPressed: onChanged == null ? null : () => _pick(context),
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(text),
    );
  }
}

/// ChoicePicker — single choice among a small set of options (chips).
class NubiaChoicePicker extends StatelessWidget {
  const NubiaChoicePicker({
    super.key,
    required this.options,
    this.value,
    this.onChanged,
  });

  final List<String> options;
  final String? value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o),
            selected: o == value,
            onSelected: onChanged == null ? null : (_) => onChanged!(o),
          ),
      ],
    );
  }
}

/// Slider — a bounded numeric input.
class NubiaSlider extends StatelessWidget {
  const NubiaSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 100,
    this.divisions,
    this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      label: value.toStringAsFixed(0),
      onChanged: onChanged,
    );
  }
}
