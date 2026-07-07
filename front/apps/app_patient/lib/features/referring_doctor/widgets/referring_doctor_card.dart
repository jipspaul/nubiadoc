import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Carte du médecin traitant déclaré (nom, spécialité, coordonnées).
class ReferringDoctorCard extends StatelessWidget {
  const ReferringDoctorCard({super.key, required this.doctor});

  final ReferringDoctor doctor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(doctor.name, style: theme.textTheme.titleMedium),
          if (doctor.specialty != null) ...[
            const SizedBox(height: 4),
            Text(doctor.specialty!, style: theme.textTheme.bodyMedium),
          ],
          if (doctor.address != null) ...[
            const SizedBox(height: 4),
            Text(doctor.address!, style: theme.textTheme.bodySmall),
          ],
          if (doctor.phone != null) ...[
            const SizedBox(height: 4),
            Text(doctor.phone!, style: theme.textTheme.bodySmall),
          ],
          if (doctor.email != null) ...[
            const SizedBox(height: 4),
            Text(doctor.email!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
