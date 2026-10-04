import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'patient_fiche.dart';
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
                        onTap: () => context.go('/patients/${p.id}'),
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
      create: (_) =>
          GetIt.instance<PatientsBloc>()
            ..add(PatientsDetailLoadRequested(patientId)),
      child: const _PatientDetailBody(),
    );
  }
}

/// #6919, maquette design-v2 — délègue entièrement l'affichage chargé à
/// `PatientFiche` (journal unifié, onglets, barre d'actions d'en-tête,
/// encart « Plan en cours »), plutôt qu'à la pile de sections historique :
/// cette dernière avait fini par cohabiter avec le nouveau journal
/// (#4971), dupliquant les rendez-vous sur l'écran réellement routé.
class _PatientDetailBody extends StatelessWidget {
  const _PatientDetailBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientsBloc, PatientsState>(
      builder: (context, state) {
        if (state is PatientDetailError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Fiche patient')),
            body: NubiaErrorWidget(
              key: const Key('patient_detail_error'),
              message: state.message,
            ),
          );
        }
        if (state is PatientDetailLoaded) {
          return PatientFiche(
            patient: state.patient,
            onNewQuote: () =>
                context.push('/devis?patientId=${state.patient.id}'),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Fiche patient')),
          body: const Center(
            key: Key('patient_detail_loading'),
            child: CircularProgressIndicator(),
          ),
        );
      },
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
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

