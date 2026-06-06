import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Static cabinet info screen — coordonnées, horaires, plan.
///
/// Cabinet data is static/demo until a CabinetRepository is available.
class CabinetInfoScreen extends StatelessWidget {
  const CabinetInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: _CabinetInfoBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _CabinetInfoBody extends StatelessWidget {
  const _CabinetInfoBody();

  @override
  Widget build(BuildContext context) {
    return const CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Text('Infos cabinet'),
          floating: true,
        ),
        const SliverPadding(
          padding: EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              _CabinetNameSection(),
              SizedBox(height: 16),
              _CabinetAddressSection(),
              SizedBox(height: 16),
              _CabinetScheduleSection(),
            ]),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _CabinetNameSection extends StatelessWidget {
  const _CabinetNameSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cabinet Nubia',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Votre cabinet dentaire',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _CabinetAddressSection extends StatelessWidget {
  const _CabinetAddressSection();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Coordonnées',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            _ContactRow(
              icon: Icons.location_on_outlined,
              text: '12 rue de la Paix, 75001 Paris',
              onTap: () => _openMap('12 rue de la Paix, 75001 Paris'),
            ),
            const SizedBox(height: 8),
            _ContactRow(
              icon: Icons.phone_outlined,
              text: '01 23 45 67 89',
              onTap: () => _callPhone('0123456789'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMap(String address) async {
    final uri = Uri(
      scheme: 'https',
      host: 'maps.google.com',
      queryParameters: {'q': address},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

// ---------------------------------------------------------------------------

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CabinetScheduleSection extends StatelessWidget {
  const _CabinetScheduleSection();

  static const _schedule = [
    _ScheduleEntry('Lundi',    '09:00 – 19:00'),
    _ScheduleEntry('Mardi',    '09:00 – 19:00'),
    _ScheduleEntry('Mercredi', '09:00 – 17:00'),
    _ScheduleEntry('Jeudi',    '09:00 – 19:00'),
    _ScheduleEntry('Vendredi', '09:00 – 18:00'),
    _ScheduleEntry('Samedi',   'Fermé'),
    _ScheduleEntry('Dimanche', 'Fermé'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Horaires',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            ..._schedule.map((e) => _ScheduleRow(entry: e)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ScheduleEntry {
  const _ScheduleEntry(this.day, this.hours);
  final String day;
  final String hours;
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.entry});

  final _ScheduleEntry entry;

  @override
  Widget build(BuildContext context) {
    final isClosed = entry.hours == 'Fermé';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(entry.day, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            entry.hours,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isClosed
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}
