import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:share_plus/share_plus.dart';

import 'patient_fiche.dart' show PatientDocumentsSection, PatientTagsSection;
import 'patients_bloc.dart';
import 'patients_event.dart';
import 'patients_state.dart';

// ---------------------------------------------------------------------------
// Liste patients
// ---------------------------------------------------------------------------

class PatientsPage extends StatelessWidget {
  const PatientsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          GetIt.instance<PatientsBloc>()..add(const PatientsLoadRequested()),
      child: const _PatientsBody(),
    );
  }
}

class _PatientsBody extends StatefulWidget {
  const _PatientsBody();

  @override
  State<_PatientsBody> createState() => _PatientsBodyState();
}

class _PatientsBodyState extends State<_PatientsBody> {
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Recherche serveur débattue (#4043) — remplace le filtrage en mémoire,
  /// qui ne scale plus au-delà de quelques centaines de dossiers. 350 ms,
  /// même délai que les autres écrans de recherche du monorepo.
  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      context.read<PatientsBloc>().add(PatientsSearchChanged(value));
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientsBloc, PatientsState>(
      builder: (context, state) {
        if (state is PatientsError) {
          return NubiaErrorWidget(
            key: const Key('patients_error'),
            message: state.message,
            onRetry: () =>
                context.read<PatientsBloc>().add(const PatientsLoadRequested()),
          );
        }
        if (state is PatientsLoaded) {
          if (state.patients.isEmpty && _query.isEmpty) {
            return const NubiaEmptyState(
              key: Key('patients_empty'),
              icon: Icons.groups_outlined,
              title: 'Aucun patient',
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: NubiaTextField(
                  key: const Key('patients_search'),
                  variant: NubiaTextFieldVariant.search,
                  hint: 'Rechercher un patient',
                  onChanged: _onSearchChanged,
                ),
              ),
              if (state.patients.isEmpty)
                const Expanded(
                  child: NubiaEmptyState(
                    key: Key('patients_search_empty'),
                    icon: Icons.search_off_outlined,
                    title: 'Aucun résultat',
                    subtitle: 'Aucun patient ne correspond à la recherche.',
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    key: const Key('patients_list'),
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: state.patients.length,
                    itemBuilder: (context, i) {
                      final p = state.patients[i];
                      return ListRow(
                        key: Key('patient_${p.id}'),
                        leading: NubiaAvatar(initials: _initials(p.fullName)),
                        title: p.fullName,
                        subtitle: p.email ?? p.phone,
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => context.push('/patients/${p.id}'),
                      );
                    },
                  ),
                ),
            ],
          );
        }
        return const _PatientsSkeleton(key: Key('patients_loading'));
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Fiche patient (detail)
// ---------------------------------------------------------------------------

class PatientDetailPage extends StatelessWidget {
  final String patientId;
  const PatientDetailPage({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<PatientsBloc>()
        ..add(PatientsDetailLoadRequested(patientId)),
      child: const _PatientDetailBody(),
    );
  }
}

class _PatientDetailBody extends StatelessWidget {
  const _PatientDetailBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PatientsBloc, PatientsState>(
      listenWhen: (_, s) =>
          (s is PatientDetailLoaded && s.notesError != null) ||
          s is PatientPdfReady ||
          s is PatientExportError,
      listener: (context, state) async {
        if (state is PatientDetailLoaded && state.notesError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.notesError!)),
          );
        }
        if (state is PatientPdfReady) {
          try {
            // XFile.fromData : aucun accès filesystem — getTemporaryDirectory
            // et dart:io lèvent sur Flutter web (#3369).
            await Share.shareXFiles(
              [
                XFile.fromData(
                  state.bytes,
                  name: state.filename,
                  mimeType: 'application/pdf',
                ),
              ],
              subject: 'Fiche patient',
            );
          } catch (_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Échec de l'export PDF")),
            );
          }
        }
        if (state is PatientExportError) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        if (state is PatientDetailError) {
          return NubiaErrorWidget(
            key: const Key('patient_detail_error'),
            message: state.message,
          );
        }
        if (state is PatientDetailLoaded) {
          return _DetailView(state: state);
        }
        return const Center(
          key: Key('patient_detail_loading'),
          child: CircularProgressIndicator(),
        );
      },
    );
  }
}

class _DetailView extends StatefulWidget {
  const _DetailView({required this.state});
  final PatientDetailLoaded state;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.state.patient;
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    NubiaAvatar(initials: _initials(p.fullName), radius: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        p.fullName,
                        key: const Key('patient_name'),
                        style: textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                if (p.birthDate != null) ...[
                  const SizedBox(height: 16),
                  _InfoRow(
                    icon: Icons.cake_outlined,
                    child: Text(
                      'Né(e) le ${_formatDate(p.birthDate!)}',
                      key: const Key('patient_birth_date'),
                    ),
                  ),
                ],
                if (p.socialSecurityNumber != null) ...[
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    child: Text(
                      'N° sécu : ${p.socialSecurityNumber!}',
                      key: const Key('patient_ssn'),
                    ),
                  ),
                ],
                if (p.email != null) ...[
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.email_outlined,
                    child: Text(p.email!, key: const Key('patient_email')),
                  ),
                ],
                if (p.phone != null) ...[
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    child: Text(p.phone!, key: const Key('patient_phone')),
                  ),
                ],
                if (p.lastVisitAt != null) ...[
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.history_outlined,
                    child: Text(
                      'Dernière visite : ${_formatDate(p.lastVisitAt!)}',
                      key: const Key('patient_last_visit'),
                    ),
                  ),
                ],
                if (p.balanceDueCents != null) ...[
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.account_balance_wallet_outlined,
                    child: Text(
                      'Solde : ${_formatBalance(p.balanceDueCents!)}',
                      key: const Key('patient_balance'),
                      style: p.balanceDueCents! > 0
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            )
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _AppointmentsHistory(appointments: widget.state.appointments),
          const SizedBox(height: 24),
          PatientTagsSection(patientId: p.id),
          const SizedBox(height: 24),
          PatientDocumentsSection(patientId: p.id),
          const SizedBox(height: 24),
          Text('Notes', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          NubiaTextField(
            key: const Key('patient_notes_field'),
            variant: NubiaTextFieldVariant.multiline,
            controller: _notesController,
            maxLines: 5,
            hint: 'Notes du praticien...',
          ),
          const SizedBox(height: 16),
          if (widget.state.notesUpdating)
            const Center(
              key: Key('notes_updating'),
              child: CircularProgressIndicator(),
            )
          else
            NubiaButton(
              key: const Key('save_notes_button'),
              label: 'Enregistrer les notes',
              icon: Icons.save_outlined,
              onPressed: () => context.read<PatientsBloc>().add(
                    PatientsNotesUpdateRequested(
                      p.id,
                      _notesController.text,
                    ),
                  ),
            ),
          const SizedBox(height: 12),
          NubiaButton(
            key: const Key('btn_dental_chart'),
            variant: NubiaButtonVariant.secondary,
            icon: Icons.grid_view_outlined,
            label: 'Schéma dentaire',
            onPressed: () => context.push('/patients/${p.id}/dental-chart'),
          ),
          const SizedBox(height: 12),
          NubiaButton(
            key: const Key('btn_export_pdf'),
            variant: NubiaButtonVariant.secondary,
            icon: Icons.picture_as_pdf_outlined,
            label: 'Exporter PDF',
            onPressed: () =>
                context.read<PatientsBloc>().add(PatientExportPdfRequested(p)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Centimes → "12,34 €" (#4045).
  String _formatBalance(int cents) =>
      '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
}

// ---------------------------------------------------------------------------

/// Ligne d'information (icône + contenu) pour la fiche patient.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.child});
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Squelette de chargement de la liste patients.
class _PatientsSkeleton extends StatelessWidget {
  const _PatientsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 8; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: NubiaSkeletonLoader(height: 56, borderRadius: 12),
          ),
      ],
    );
  }
}

/// Initiales (max 2 lettres) à partir d'un nom complet.
String _initials(String fullName) {
  final parts =
      fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

/// Historique des RDV du patient dans le cabinet (#3372).
class _AppointmentsHistory extends StatelessWidget {
  const _AppointmentsHistory({required this.appointments});

  final List<CabinetAppointment> appointments;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Historique des rendez-vous', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        if (appointments.isEmpty)
          Text(
            'Aucun rendez-vous enregistré.',
            key: const Key('patient_appointments_empty'),
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          NubiaCard(
            key: const Key('patient_appointments_history'),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, a) in appointments.take(10).indexed)
                  ListRow(
                    key: Key('patient_appt_${a.id}'),
                    leading: const Icon(Icons.event_outlined),
                    title:
                        '${_formatDateTime(a.startsAt)} · ${a.practitionerName}',
                    subtitle: a.motif,
                    showDivider: i != appointments.take(10).length - 1,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year} $hh:$min';
  }
}
