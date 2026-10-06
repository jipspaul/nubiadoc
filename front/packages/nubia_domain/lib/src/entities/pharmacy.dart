import 'package:equatable/equatable.dart';

/// Pharmacie de l'annuaire public (GET /v1/pharmacies).
class Pharmacy extends Equatable {
  final String id;
  final String name;
  final String? address;
  final String? phone;

  /// Distance en mètres depuis le point de recherche (si lat/lng fournis).
  final double? distanceM;

  /// Horaires d'ouverture (`pharmacy.opening_hours`, #8061) — clé = jour
  /// abrégé (lun/mar/mer/jeu/ven/sam/dim), valeur = plage "HH:MM-HH:MM".
  /// Jour absent ou `null` → fermé ce jour-là.
  final Map<String, String>? openingHours;

  const Pharmacy({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.distanceM,
    this.openingHours,
  });

  double? get distanceKm => distanceM == null ? null : distanceM! / 1000.0;

  /// Clés jour dans l'ordre ISO (lundi = 1) — mêmes abréviations que
  /// `cabinet.settings->>'horaires'`.
  static const _dayKeys = [
    'lun',
    'mar',
    'mer',
    'jeu',
    'ven',
    'sam',
    'dim',
  ];

  /// Statut d'ouverture à l'instant [now] (#8061) — `null` si aucun horaire
  /// n'est connu pour cette pharmacie (carte sans encart horaires).
  PharmacyOpeningStatus? openingStatusAt(DateTime now) {
    final hours = openingHours;
    if (hours == null || hours.isEmpty) return null;

    final range = hours[_dayKeys[now.weekday - 1]];
    if (range != null) {
      final parts = range.split('-');
      final open = parts.length == 2 ? _minutesOf(parts[0]) : null;
      final close = parts.length == 2 ? _minutesOf(parts[1]) : null;
      if (open != null && close != null) {
        final minutesNow = now.hour * 60 + now.minute;
        if (minutesNow >= open && minutesNow < close) {
          return PharmacyOpeningStatus(
            isOpen: true,
            label: "Ouvert jusqu'à ${_frenchHour(parts[1])}",
          );
        }
      }
    }
    return const PharmacyOpeningStatus(isOpen: false, label: 'Fermé');
  }

  static int? _minutesOf(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static String _frenchHour(String hhmm) => hhmm.replaceFirst(':', 'h');

  @override
  List<Object?> get props => [id];
}

/// Statut d'ouverture d'une pharmacie à un instant donné (#8061).
class PharmacyOpeningStatus extends Equatable {
  final bool isOpen;

  /// Libellé prêt à afficher (ex. « Ouvert jusqu'à 19h30 », « Fermé »).
  final String label;

  const PharmacyOpeningStatus({required this.isOpen, required this.label});

  @override
  List<Object?> get props => [isOpen, label];
}
