import 'package:flutter/material.dart';

import '../widgets/nubia_avatar.dart';
import '../widgets/nubia_badge.dart';
import '../widgets/nubia_button.dart';
import '../widgets/nubia_card.dart';
import '../widgets/nubia_chip.dart';
import '../widgets/nubia_primitives.dart';
import '../widgets/nubia_text_field.dart';
import '../widgets/status_pill.dart';

/// Single source of truth mapping A2UI catalog prop strings to Nubia widgets.
///
/// The A2UI catalog (`packages/nubia_a2ui/assets/catalog.json`) declares the
/// same enum value strings used here. A unit test in `nubia_a2ui` asserts every
/// catalog enum value resolves through these maps, keeping catalog ↔ renderer
/// in sync.
class DsProps {
  DsProps._();

  // --- enum string maps -----------------------------------------------------

  static const Map<String, NubiaButtonVariant> buttonVariants = {
    'primary': NubiaButtonVariant.primary,
    'secondary': NubiaButtonVariant.secondary,
    'tertiary': NubiaButtonVariant.tertiary,
    'destructive': NubiaButtonVariant.destructive,
  };

  static const Map<String, NubiaButtonSize> buttonSizes = {
    'sm': NubiaButtonSize.sm,
    'md': NubiaButtonSize.md,
    'lg': NubiaButtonSize.lg,
  };

  static const Map<String, NubiaTextFieldVariant> textFieldVariants = {
    'outlined': NubiaTextFieldVariant.outlined,
    'filled': NubiaTextFieldVariant.filled,
    'search': NubiaTextFieldVariant.search,
    'password': NubiaTextFieldVariant.password,
    'multiline': NubiaTextFieldVariant.multiline,
    'withSuffix': NubiaTextFieldVariant.withSuffix,
  };

  static const Map<String, NubiaChipVariant> chipVariants = {
    'filter': NubiaChipVariant.filter,
    'choice': NubiaChipVariant.choice,
    'input': NubiaChipVariant.input,
  };

  static const Map<String, NubiaBadgeVariant> badgeVariants = {
    'neutral': NubiaBadgeVariant.neutral,
    'info': NubiaBadgeVariant.info,
    'success': NubiaBadgeVariant.success,
    'warning': NubiaBadgeVariant.warning,
    'error': NubiaBadgeVariant.error,
  };

  static const Map<String, StatusPillVariant> statusVariants = {
    'info': StatusPillVariant.info,
    'success': StatusPillVariant.success,
    'warning': StatusPillVariant.warning,
    'error': StatusPillVariant.error,
  };

  static const Map<String, NubiaCardState> cardStates = {
    'static': NubiaCardState.static_,
    'interactive': NubiaCardState.interactive,
    'selected': NubiaCardState.selected,
  };

  // --- prop helpers ---------------------------------------------------------

  static String str(Map<String, dynamic> p, String key, [String fallback = '']) =>
      p[key]?.toString() ?? fallback;

  static bool boolean(Map<String, dynamic> p, String key, [bool fallback = false]) {
    final v = p[key];
    if (v is bool) return v;
    if (v is String) return v == 'true';
    return fallback;
  }

  static double number(Map<String, dynamic> p, String key, double fallback) {
    final v = p[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  // --- builders (catalog component -> Nubia widget) -------------------------

  static Widget button(Map<String, dynamic> p, {VoidCallback? onPressed}) {
    return NubiaButton(
      label: str(p, 'label'),
      variant: buttonVariants[str(p, 'variant', 'primary')] ?? NubiaButtonVariant.primary,
      size: buttonSizes[str(p, 'size', 'md')] ?? NubiaButtonSize.md,
      isLoading: boolean(p, 'isLoading'),
      onPressed: onPressed,
    );
  }

  static Widget text(Map<String, dynamic> p) {
    final maxLines = p['maxLines'];
    return Text(
      str(p, 'value'),
      maxLines: maxLines is int ? maxLines : null,
      overflow: maxLines is int ? TextOverflow.ellipsis : null,
    );
  }

  static Widget textField(Map<String, dynamic> p, {ValueChanged<String>? onChanged}) {
    return NubiaTextField(
      variant: textFieldVariants[str(p, 'variant', 'outlined')] ?? NubiaTextFieldVariant.outlined,
      label: p['label'] as String?,
      hint: p['hint'] as String?,
      errorText: p['errorText'] as String?,
      enabled: boolean(p, 'enabled', true),
      onChanged: onChanged,
    );
  }

  static Widget chip(Map<String, dynamic> p, {VoidCallback? onTap}) {
    return NubiaChip(
      label: str(p, 'label'),
      variant: chipVariants[str(p, 'variant', 'filter')] ?? NubiaChipVariant.filter,
      selected: boolean(p, 'selected'),
      onTap: onTap,
    );
  }

  static Widget badge(Map<String, dynamic> p) {
    final variant = badgeVariants[str(p, 'variant', 'neutral')] ?? NubiaBadgeVariant.neutral;
    final count = p['count'];
    if (count is num) {
      return NubiaBadge.count(count: count.toInt(), variant: variant);
    }
    return NubiaBadge.label(label: str(p, 'label'), variant: variant);
  }

  static Widget avatar(Map<String, dynamic> p) {
    return NubiaAvatar(
      imageUrl: p['src'] as String?,
      initials: str(p, 'initials'),
      radius: number(p, 'radius', 21),
    );
  }

  static Widget statusPill(Map<String, dynamic> p) {
    return StatusPill(
      label: str(p, 'label'),
      variant: statusVariants[str(p, 'status', 'info')] ?? StatusPillVariant.info,
    );
  }

  static Widget checkbox(Map<String, dynamic> p, {ValueChanged<bool>? onChanged}) {
    return NubiaCheckbox(
      value: boolean(p, 'value'),
      label: p['label'] as String?,
      onChanged: onChanged,
    );
  }

  static Widget slider(Map<String, dynamic> p, {ValueChanged<double>? onChanged}) {
    return NubiaSlider(
      value: number(p, 'value', 0),
      min: number(p, 'min', 0),
      max: number(p, 'max', 100),
      onChanged: onChanged,
    );
  }

  static Widget choicePicker(Map<String, dynamic> p, {ValueChanged<String>? onChanged}) {
    final options = (p['options'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    return NubiaChoicePicker(
      options: options,
      value: p['value'] as String?,
      onChanged: onChanged,
    );
  }
}
