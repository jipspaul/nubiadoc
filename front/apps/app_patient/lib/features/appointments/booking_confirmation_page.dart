import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

const _weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const _months = [
  'jan',
  'fév',
  'mar',
  'avr',
  'mai',
  'jun',
  'jul',
  'aoû',
  'sep',
  'oct',
  'nov',
  'déc',
];

String _dayHeader(DateTime dt) {
  final local = dt.toLocal();
  return '${_weekdays[local.weekday - 1]} ${local.day} ${_months[local.month - 1]}';
}

String _hhmm(DateTime dt) {
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// #4534 : écran de confirmation dédié après une prise de RDV réussie —
/// remplace le seul snackbar fugace (« Demande de rendez-vous envoyée » puis
/// retour direct à l'accueil), qui ne rassurait pas assez l'utilisateur sur
/// le fait que sa demande a bien été enregistrée.
///
/// Retourne `true` via [Navigator.pop] si l'utilisateur choisit « Voir mes
/// RDV » (l'appelant peut alors basculer l'onglet), `false`/`null` sinon.
class BookingConfirmationPage extends StatelessWidget {
  const BookingConfirmationPage({required this.appointment, super.key});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demande envoyée'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Icon(
                Icons.check_circle_outline,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Demande de rendez-vous envoyée',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'En attente de confirmation par le cabinet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              NubiaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.practitionerSpecialty.isEmpty
                          ? appointment.practitionerName
                          : '${appointment.practitionerName} · ${appointment.practitionerSpecialty}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_dayHeader(appointment.startsAt)} à ${_hhmm(appointment.startsAt)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (appointment.motif.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        appointment.motif,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    if (appointment.cabinetAddress != null &&
                        appointment.cabinetAddress!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        appointment.cabinetAddress!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: NubiaButton(
                  key: const Key('booking_confirmation_view_appointments'),
                  label: 'Voir mes RDV',
                  size: NubiaButtonSize.lg,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  key: const Key('booking_confirmation_dismiss'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Continuer ma recherche'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
