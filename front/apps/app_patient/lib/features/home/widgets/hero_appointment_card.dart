import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../../router/app_router.dart';

/// Carte héros pleine largeur en tête de l'accueil patient (maquette
/// `patient-accueil.png`, note #1).
///
/// Quoi : la donnée que le patient vient chercher (quand / où) plutôt qu'un
/// simple compteur — remplace la tuile « Prochain RDV » (#5198).
/// Quand : rendue en tête de la `ListView` de `_HomeContent`
/// (`home_page.dart`), alimentée par `HomeLoaded.nextAppointment`.
/// Pourquoi : [nextAppointment] vient du bloc (aucun appel réseau ici).
/// Échec : RDV à venir (`upcomingAppointments > 0`) mais [nextAppointment]
/// non chargé → carte masquée plutôt que d'inventer un contenu hors
/// maquette ; sans RDV à venir → CTA de prise de rendez-vous (#5199).
class HeroAppointmentCard extends StatelessWidget {
  const HeroAppointmentCard({
    super.key,
    required this.upcomingAppointments,
    required this.nextAppointment,
  });

  final int upcomingAppointments;
  final Appointment? nextAppointment;

  @override
  Widget build(BuildContext context) {
    final appointment = nextAppointment;
    if (appointment != null) {
      return _HeroAppointmentDetailCard(appointment: appointment);
    }
    if (upcomingAppointments > 0) {
      return const SizedBox.shrink();
    }
    return const _HeroAppointmentCta();
  }
}

// ---------------------------------------------------------------------------

/// CTA « Prendre rendez-vous » — état sans RDV à venir (#5199).
class _HeroAppointmentCta extends StatelessWidget {
  const _HeroAppointmentCta();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        // Ombre douce `sm` : 0 1px 2px rgba(28,25,23,.05).
        boxShadow: [
          BoxShadow(
            color: NubiaColors.n900.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        key: const Key('hero_appointment_cta'),
        color: NubiaColors.brand700,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRouter.appointments),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.event_available, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prendre rendez-vous',
                        style: textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Aucun rendez-vous à venir — trouvez un créneau.',
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Détail du prochain RDV — fond `brand/700`, radius 22, texte blanc
/// (maquette `patient-accueil.png`, note #1) : pilule de délai relatif,
/// date, praticien · motif, adresse, boutons Itinéraire / Préparer.
class _HeroAppointmentDetailCard extends StatelessWidget {
  const _HeroAppointmentDetailCard({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final address = appointment.cabinetAddress;

    return Container(
      key: const Key('hero_appointment_detail'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NubiaColors.brand700,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: NubiaColors.brand700.withValues(alpha: 0.55),
            blurRadius: 30,
            offset: const Offset(0, 14),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RelativeDelayPill(startsAt: appointment.startsAt),
          const SizedBox(height: 14),
          Text(
            _formatDateTime(appointment.startsAt),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${appointment.practitionerName} · ${appointment.motif}',
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          if (address != null) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.16)),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place,
                    size: 16, color: Colors.white.withValues(alpha: 0.78)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    address,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const Key('hero_directions_button'),
                    onPressed: address == null
                        ? null
                        : () => openMapsDirections(address),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: NubiaColors.brand700,
                    ),
                    icon: const Icon(Icons.directions, size: 18),
                    label: const Text('Itinéraire'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    key: const Key('hero_prepare_button'),
                    onPressed: () =>
                        context.push('/rdv/${appointment.id}/prepare'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.42)),
                    ),
                    icon: const Icon(Icons.checklist, size: 18),
                    label: const Text('Préparer'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _weekdays = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];

  static const _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  // #3856 : `startsAtUtc` vient de DateTime.parse() sur un ISO avec offset
  // +00:00 → isUtc == true. Lire .day/.hour bruts affiche la date/heure UTC
  // au lieu de locale (-2h en été/-1h en hiver pour Europe/Paris).
  static String _formatDateTime(DateTime startsAtUtc) {
    final local = startsAtUtc.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${_weekdays[local.weekday - 1]} ${local.day} '
        '${_months[local.month - 1]} · $hh:$mm';
  }
}

// ---------------------------------------------------------------------------

/// Pilule de délai relatif (« Dans N jours » / « Demain » / « Aujourd'hui »)
/// calculée depuis [startsAt] — fond blanc 16 %, radius 99.
class _RelativeDelayPill extends StatelessWidget {
  const _RelativeDelayPill({required this.startsAt});

  final DateTime startsAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            _relativeDelay(startsAt),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // #6287 : `diff < 0` (RDV `checked_in`/`in_progress` déjà commencé, encore
  // renvoyé par `filter=upcoming` dans sa fenêtre glissante de 1 jour) était
  // replié sur "Aujourd'hui" — contradiction avec une date affichée d'hier.
  static String _relativeDelay(DateTime startsAtUtc) {
    final local = startsAtUtc.toLocal();
    final now = DateTime.now();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    if (diff < 0) return 'En cours';
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Demain';
    return 'Dans $diff jours';
  }
}
