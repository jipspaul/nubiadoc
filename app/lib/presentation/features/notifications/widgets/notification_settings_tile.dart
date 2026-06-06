import 'package:flutter/material.dart';

/// A single toggle row in the notification settings list.
class NotificationSettingsTile extends StatelessWidget {
  const NotificationSettingsTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SwitchListTile(
      secondary: Icon(icon, color: colorScheme.onSurfaceVariant),
      title: Text(label),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}
