import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import 'patients_bloc.dart';
import 'patients_event.dart';
import 'patients_state.dart';

/// Écran "Patients" côté secrétariat — liste + fiche administrative.
///
/// Cloisonnement : ZÉRO donnée clinique. Seules les informations
/// administratives (identité, contact, dernière visite) sont exposées.
class PatientsPage extends StatefulWidget {
  const PatientsPage({super.key, this.openPatientId});

  /// Id d'un patient à ouvrir automatiquement (fiche détail) au chargement —
  /// utilisé par la recherche globale (#5579) pour naviguer directement sur
  /// le résultat sélectionné plutôt que la liste seule.
  final String? openPatientId;

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  String _query = '';
  Timer? _debounce;
  bool _openPatientHandled = false;

  /// Id du patient affiché dans le volet latéral (design-v2, #5116) — la
  /// fiche n'est plus une `showModalBottomSheet` mais un panneau persistant
  /// à droite de la liste : sélectionner un autre patient met juste à jour
  /// cet id, sans fermer/rouvrir le panneau.
  String? _selectedPatientId;

  void _selectPatient(String patientId) {
    setState(() => _selectedPatientId = patientId);
  }

  void _closePatientSheet() {
    setState(() => _selectedPatientId = null);
  }

  CabinetPatient? _findPatient(List<CabinetPatient> patients, String? id) {
    if (id == null) return null;
    for (final p in patients) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Filtres rapides à bascule de la barre d'outils (design-v2, note #5) :
  /// Impayés / Alertes / Sans RDV à venir. Combinés en ET quand plusieurs
  /// sont actifs, appliqués côté client sur `state.patients` — aucun fetch
  /// dédié par filtre.
  final Set<_QuickFilter> _activeFilters = {};

  void _toggleFilter(_QuickFilter filter) {
    setState(() {
      if (!_activeFilters.remove(filter)) _activeFilters.add(filter);
    });
  }

  List<CabinetPatient> _applyFilters(List<CabinetPatient> patients) {
    if (_activeFilters.isEmpty) return patients;
    return patients.where((p) {
      for (final filter in _activeFilters) {
        if (!filter.matches(p)) return false;
      }
      return true;
    }).toList();
  }

  /// Total de patients du cabinet (design-v2, note #7 — « N résultats sur
  /// M »). Capturé sur le dernier chargement non filtré (`_query` vide) :
  /// il n'existe pas d'endpoint de comptage dédié, donc M reste figé sur la
  /// dernière liste complète tant qu'une recherche est en cours.
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    context.read<PatientsBloc>().add(const PatientsLoadRequested());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Recherche serveur débattue (#4043) — 350 ms, même délai que les autres
  /// écrans de recherche du monorepo (referring_doctor_search_page.dart,
  /// pharmacy_search_page.dart).
  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      context.read<PatientsBloc>().add(PatientsSearchChanged(value));
    });
  }

  Future<void> _onCreate() async {
    final created = await context.push<CabinetPatient>(AppRouter.patientNew);
    if (created != null && context.mounted) {
      context.read<PatientsBloc>().add(const PatientsLoadRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    // design-v2 (#5121) : le FAB remonte dans la barre d'outils avec son
    // raccourci ⌘N, même pattern que stock_page.dart (#5188).
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _onCreate,
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(NubiaL10n.patients),
          actions: [
            IconButton(
              tooltip: NubiaL10n.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: () => context
                  .read<PatientsBloc>()
                  .add(const PatientsLoadRequested()),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: NubiaButton(
                key: const Key('patients_new_button'),
                label: 'Nouveau patient',
                icon: Icons.person_add,
                onPressed: _onCreate,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: NubiaBadge.label(label: '⌘N'),
            ),
          ],
        ),
        body: BlocBuilder<PatientsBloc, PatientsState>(
          builder: (context, state) {
            if (state is PatientsLoaded) {
              if (widget.openPatientId != null && !_openPatientHandled) {
                _openPatientHandled = true;
                CabinetPatient? match;
                for (final p in state.patients) {
                  if (p.id == widget.openPatientId) {
                    match = p;
                    break;
                  }
                }
                if (match != null) {
                  final patientId = match.id;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _selectPatient(patientId);
                  });
                }
              }
              if (state.patients.isEmpty && _query.isEmpty) {
                return const NubiaEmptyState(
                  icon: Icons.person_outline,
                  title: 'Aucun patient',
                  subtitle: NubiaL10n.noPatients,
                );
              }
              if (_query.isEmpty) {
                _totalCount = state.patients.length;
              }
              final filteredPatients = _applyFilters(state.patients);
              final selectedPatient =
                  _findPatient(state.patients, _selectedPatientId);
              // Le contenu maître (recherche + filtres + tableau) reste un
              // widget à part entière : le volet latéral se contente de
              // l'accompagner dans un `Row` — pas de fusion des deux (design-
              // v2, #5116 — « fiche reste un composant distinct de la liste »).
              final listColumn = Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Rechercher un patient',
                            ),
                            onChanged: _onSearchChanged,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${state.patients.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: NubiaColors.n900,
                                  ),
                                ),
                                TextSpan(
                                  text: ' résultats sur $_totalCount',
                                  style: const TextStyle(
                                    color: NubiaColors.n500,
                                  ),
                                ),
                              ],
                            ),
                            key: const Key('patients_search_results_count'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Wrap(
                      key: const Key('patients_quick_filters'),
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final filter in _QuickFilter.values)
                          _QuickFilterChip(
                            key: Key('patients_quick_filter_${filter.name}'),
                            label: filter.label,
                            count: filter.countIn(state.patients),
                            selected: _activeFilters.contains(filter),
                            icon: filter.icon,
                            iconColor: filter.iconColor,
                            onTap: () => _toggleFilter(filter),
                          ),
                      ],
                    ),
                  ),
                  if (state.patients.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          'Aucun patient ne correspond à « $_query ».',
                          key: const Key('patients_search_no_results'),
                        ),
                      ),
                    )
                  else if (filteredPatients.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          'Aucun patient ne correspond aux filtres '
                          'sélectionnés.',
                          key: const Key('patients_filters_no_results'),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Column(
                        children: [
                          const PatientsTableHeader(),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 16),
                              itemCount: filteredPatients.length,
                              itemBuilder: (_, i) {
                                final rowPatient = filteredPatients[i];
                                return PatientTableRow(
                                  patient: rowPatient,
                                  selected:
                                      rowPatient.id == _selectedPatientId,
                                  onTap: () => _selectPatient(rowPatient.id),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: listColumn),
                  if (selectedPatient != null)
                    SizedBox(
                      width: 396,
                      child: _PatientSheet(
                        key: Key('patient_sheet_${selectedPatient.id}'),
                        patient: selectedPatient,
                        onClose: _closePatientSheet,
                      ),
                    ),
                ],
              );
            }
            if (state is PatientsError) {
              return NubiaErrorWidget(
                message: state.message,
                onRetry: () => context
                    .read<PatientsBloc>()
                    .add(const PatientsLoadRequested()),
              );
            }
            // PatientsInitial, PatientsLoading
            return const _PatientsSkeleton();
          },
        ),
      ),
    );
  }
}

/// Filtres rapides de la barre d'outils Fiches patients (design-v2, note
/// #5) : Impayés / Alertes / Sans RDV à venir. `matches`/`countIn` lisent
/// exclusivement les champs déjà présents sur [CabinetPatient] (aucun fetch
/// dédié) — `hasActiveAlerts`/`hasUpcomingAppointment` restent `null` tant
/// que la liste paginée n'est pas enrichie par le ticket dépendant, auquel
/// cas le filtre correspondant ne retient aucun patient.
enum _QuickFilter {
  unpaid('Impayés'),
  alerts('Alertes'),
  noUpcomingAppointment('Sans RDV à venir');

  const _QuickFilter(this.label);

  final String label;

  IconData? get icon => this == _QuickFilter.unpaid ? Icons.error : null;

  Color? get iconColor =>
      this == _QuickFilter.unpaid ? NubiaColors.dangerFg : null;

  bool matches(CabinetPatient patient) {
    switch (this) {
      case _QuickFilter.unpaid:
        return (patient.balanceDueCents ?? 0) > 0;
      case _QuickFilter.alerts:
        return patient.hasActiveAlerts == true;
      case _QuickFilter.noUpcomingAppointment:
        return patient.hasUpcomingAppointment == false;
    }
  }

  int countIn(List<CabinetPatient> patients) =>
      patients.where(matches).length;
}

/// Puce de filtre rapide à bascule (design-v2, `.fltr`) : libellé + compteur
/// gris tabular-nums, fond `n100` quand actif (`.fc.on`).
class _QuickFilterChip extends StatelessWidget {
  const _QuickFilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconColor,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? NubiaColors.n100 : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? NubiaColors.n100 : tokens.borderDefault,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          toggled: selected,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: iconColor ?? cs.error),
                  const SizedBox(width: 4),
                ],
                Text(label, style: textTheme.bodyMedium),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: textTheme.bodyMedium?.copyWith(
                    color: NubiaColors.n500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Formate une date en « jj/mm/aaaa ».
String _formatDate(DateTime dt) => '${dt.day.toString().padLeft(2, '0')}/'
    '${dt.month.toString().padLeft(2, '0')}/'
    '${dt.year}';

/// Largeurs des colonnes du tableau patients (design-v2, note #5) — grille
/// `1fr 214px 116px 108px 176px 34px`, partagée entre [PatientsTableHeader]
/// et [PatientTableRow] pour rester alignées.
class _PatientColumns {
  const _PatientColumns._();

  static const double gap = 16;
  static const double contact = 214;
  static const double lastVisit = 116;
  static const double balance = 108;
  static const double alerts = 176;
  static const double chevron = 20;
}

/// En-tête de colonnes du tableau patients (design-v2, note #5).
class PatientsTableHeader extends StatelessWidget {
  const PatientsTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: tokens.textTertiary,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          const SizedBox(width: 40 + 12), // aligné sous l'avatar de la ligne
          Expanded(child: Text('Patient', style: style)),
          const SizedBox(width: _PatientColumns.gap),
          SizedBox(width: _PatientColumns.contact, child: Text('Contact', style: style)),
          const SizedBox(width: _PatientColumns.gap),
          SizedBox(
            width: _PatientColumns.lastVisit,
            child: Text('Dernière visite', style: style),
          ),
          const SizedBox(width: _PatientColumns.gap),
          SizedBox(
            width: _PatientColumns.balance,
            child: Text('Solde', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: _PatientColumns.gap),
          SizedBox(
            width: _PatientColumns.alerts,
            child: Text('Alertes & étiquettes', style: style),
          ),
          const SizedBox(width: _PatientColumns.gap),
          const SizedBox(width: _PatientColumns.chevron),
        ],
      ),
    );
  }
}

/// Contenu de la colonne Contact (design-v2, note #5) : téléphone + email,
/// ou tuteur légal quand renseigné (`GuardianshipLink`, #4091). Aucune
/// donnée clinique — cloisonnement secrétariat.
Widget _contactColumn(BuildContext context, CabinetPatient patient) {
  final textTheme = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  final style = textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);

  final guardians = patient.guardians ?? const [];
  if (guardians.isNotEmpty) {
    return Text(
      'tuteur : ${guardians.first.fullName}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  final phone = patient.phone;
  final email = patient.email;
  final hasPhone = phone != null && phone.isNotEmpty;
  final hasEmail = email != null && email.isNotEmpty;
  if (!hasPhone && !hasEmail) return const SizedBox.shrink();

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (hasPhone)
        Text(
          phone,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(fontFeatures: tabularFigures),
        ),
      if (hasEmail) ...[
        if (hasPhone) const SizedBox(height: 2),
        Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      ],
    ],
  );
}

/// Âge en années révolues à la date du jour.
int _ageInYears(DateTime birthDate) {
  final now = DateTime.now();
  var age = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
    age--;
  }
  return age;
}

/// Ligne du tableau patients (design-v2, note #5) : cinq colonnes alignées
/// — Patient (avatar + nom + naissance/âge), Contact, Dernière visite,
/// Solde (aligné à droite), Alertes & étiquettes — puis le chevron.
class PatientTableRow extends StatelessWidget {
  const PatientTableRow({
    super.key,
    required this.patient,
    this.selected = false,
    this.onTap,
  });

  final CabinetPatient patient;

  /// Ligne surlignée (design-v2, `.row.on`) quand la fiche de ce patient est
  /// ouverte dans le volet latéral — fond `brand50` + accent `brand700` sur
  /// la bordure gauche.
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final birthDate = patient.birthDate;
    final lastVisitAt = patient.lastVisitAt;
    final balanceCents = patient.balanceDueCents ?? 0;
    final balanceDue = balanceCents > 0;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            NubiaAvatar(
              initials: NubiaInitials.of(patient.fullName),
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (birthDate != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDate(birthDate)} · ${_ageInYears(birthDate)} ans',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: _PatientColumns.gap),
            SizedBox(
              width: _PatientColumns.contact,
              child: _contactColumn(context, patient),
            ),
            const SizedBox(width: _PatientColumns.gap),
            SizedBox(
              width: _PatientColumns.lastVisit,
              child: Text(
                lastVisitAt != null ? _formatDate(lastVisitAt) : '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            const SizedBox(width: _PatientColumns.gap),
            SizedBox(
              width: _PatientColumns.balance,
              child: Text(
                NubiaMoney.formatCents(balanceCents),
                textAlign: TextAlign.right,
                style: textTheme.bodyMedium?.copyWith(
                  color: balanceDue ? NubiaColors.dangerFg : NubiaColors.n500,
                  fontWeight: balanceDue ? FontWeight.w600 : FontWeight.w400,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            const SizedBox(width: _PatientColumns.gap),
            SizedBox(
              width: _PatientColumns.alerts,
              child: Align(
                alignment: Alignment.centerLeft,
                child: PatientAlertBadge(patient: patient),
              ),
            ),
            const SizedBox(width: _PatientColumns.gap),
            SizedBox(
              width: _PatientColumns.chevron,
              child: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: Key('patient_row_${patient.id}'),
          color: selected ? NubiaColors.brand50 : Colors.transparent,
          // `foregroundDecoration` (pas `decoration`) : peint la bordure
          // par-dessus le contenu sans lui ajouter de padding implicite,
          // pour ne pas décaler les colonnes fixes du tableau (cf. #5116).
          foregroundDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? NubiaColors.brand700 : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: content,
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
      ],
    );
  }
}

/// Sévérité d'une pastille d'alerte/étiquette (design-v2, note #2), mappée
/// sur les tokens sémantiques Nubia.
enum _AlertSeverity { danger, warn, info, neutral }

class _AlertPastilleData {
  const _AlertPastilleData(this.label, this.severity);

  final String label;
  final _AlertSeverity severity;
}

/// Pastilles d'alerte/étiquette accueil (#4093/#4094, design-v2 note #2) :
/// remplace l'ancien `Tooltip` sur icône, dont le contenu n'apparaissait
/// qu'au survol (jamais au clavier). Lues directement depuis les champs déjà
/// chargés par la liste (`CabinetPatient`) — plus de fetch par ligne. Même
/// best-effort qu'avant : `hasActiveAlerts`/`noShowCount`/`guardians`
/// restent `null` tant que l'endpoint liste n'est pas enrichi (ticket
/// dépendant), la ligne s'affiche alors simplement sans pastille.
class PatientAlertBadge extends StatelessWidget {
  const PatientAlertBadge({super.key, required this.patient});

  final CabinetPatient patient;

  List<_AlertPastilleData> get _pastilles {
    final pastilles = <_AlertPastilleData>[];
    final balanceDue = patient.balanceDueCents ?? 0;
    if (balanceDue > 0) {
      pastilles
          .add(const _AlertPastilleData('Impayé', _AlertSeverity.danger));
    } else if (patient.hasActiveAlerts == true) {
      pastilles.add(
        const _AlertPastilleData('Alerte accueil', _AlertSeverity.danger),
      );
    }
    final noShowCount = patient.noShowCount ?? 0;
    if (noShowCount > 0) {
      pastilles.add(
        _AlertPastilleData(
          '$noShowCount lapin${noShowCount > 1 ? 's' : ''}',
          _AlertSeverity.warn,
        ),
      );
    }
    if ((patient.guardians ?? const []).isNotEmpty) {
      pastilles.add(
        const _AlertPastilleData('Mineur · tuteur', _AlertSeverity.info),
      );
    }
    return pastilles;
  }

  @override
  Widget build(BuildContext context) {
    final pastilles = _pastilles;
    if (pastilles.isEmpty) return const SizedBox.shrink();
    return Wrap(
      key: const Key('patient_alert_badge'),
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final pastille in pastilles) _AlertPastille(data: pastille),
      ],
    );
  }
}

/// Étiquette design-v2 : `font-size:10.5px;font-weight:600;
/// border-radius:5px;padding:2px 7px` (verbatim maquette, note #2).
class _AlertPastille extends StatelessWidget {
  const _AlertPastille({required this.data});

  final _AlertPastilleData data;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final (Color bg, Color fg, Color border) = switch (data.severity) {
      _AlertSeverity.danger => (
          tokens.dangerBg,
          tokens.dangerFg,
          NubiaColors.dangerBorder
        ),
      _AlertSeverity.warn => (
          tokens.warningBg,
          tokens.warningFg,
          NubiaColors.warningBorder
        ),
      _AlertSeverity.info => (
          tokens.infoBg,
          tokens.infoFg,
          NubiaColors.infoBorder
        ),
      _AlertSeverity.neutral => (
          tokens.neutralBg,
          tokens.neutralFg,
          NubiaColors.n200
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: border),
      ),
      child: Text(
        data.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// Fiche patient (informations administratives) — volet latéral persistant
/// (design-v2, #5116) : bordure gauche `borderSubtle`, fermeture explicite
/// via [onClose], sans repli sur `showModalBottomSheet`.
///
/// design-v2 (#5115) : chargement unique. Ouvrir un patient déclenchait
/// jusqu'ici quatre fetch indépendants (`GetCabinetPatient`,
/// `ListPatientTags`, `ListPatientDocuments`, `ListPatientAlerts`), chacun
/// avec son propre état de chargement et un échec silencieux
/// (`SizedBox.shrink()`) — une fiche pouvait s'afficher sans solde ni
/// étiquettes sans que rien ne le signale. Les 4 appels partent désormais
/// en parallèle depuis un seul point de déclenchement (`_load`), avec un
/// état de chargement unique et un échec visible par section. Les alertes
/// restent best-effort (#4093/#4094) : leur échec seul n'empêche pas de
/// consulter le reste de la fiche, mais devient visible.
class _PatientSheet extends StatefulWidget {
  const _PatientSheet({
    super.key,
    required this.patient,
    required this.onClose,
  });

  final CabinetPatient patient;
  final VoidCallback onClose;

  @override
  State<_PatientSheet> createState() => _PatientSheetState();
}

class _PatientSheetState extends State<_PatientSheet> {
  bool _loading = true;
  CabinetPatient? _patientDetail;
  String? _balanceError;
  List<PatientTag>? _tags;
  String? _tagsError;
  List<PatientDocument>? _documents;
  String? _documentsError;
  List<PatientAlert>? _alerts;
  String? _alertsError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final detailFuture =
        GetIt.instance<GetCabinetPatientUseCase>()(widget.patient.id);
    final tagsFuture =
        GetIt.instance<ListPatientTagsUseCase>()(widget.patient.id);
    final documentsFuture =
        GetIt.instance<ListPatientDocumentsUseCase>()(widget.patient.id);
    final alertsFuture =
        GetIt.instance<ListPatientAlertsUseCase>()(widget.patient.id);

    // Synchronisation des 4 appels sans dépendre de leur type de retour
    // respectif (chaque future est ensuite ré-attendue individuellement
    // ci-dessous — déjà résolue, donc immédiate).
    await Future.wait<Object?>(<Future<Object?>>[
      detailFuture,
      tagsFuture,
      documentsFuture,
      alertsFuture,
    ]);
    if (!mounted) return;

    final detailResult = await detailFuture;
    final tagsResult = await tagsFuture;
    final documentsResult = await documentsFuture;
    final alertsResult = await alertsFuture;

    setState(() {
      detailResult.fold(
        (failure) => _balanceError = failure.message,
        (patient) => _patientDetail = patient,
      );
      tagsResult.fold(
        (failure) => _tagsError = failure.message,
        (tags) => _tags = tags,
      );
      documentsResult.fold(
        (failure) => _documentsError = failure.message,
        (documents) => _documents = documents,
      );
      // Best-effort (#4093/#4094) : un échec des alertes seules ne bloque
      // pas le reste de la fiche — voir _PatientSheetAlertIndicator.
      alertsResult.fold(
        (failure) => _alertsError = failure.message,
        (alerts) => _alerts = alerts,
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final patient = widget.patient;

    // Uniquement des champs administratifs (cloisonnement : zéro clinique).
    // Ces champs viennent de la liste (déjà en mémoire) — pas du fetch
    // consolidé ci-dessus, donc toujours disponibles immédiatement.
    final rows = <(IconData, String, String)>[
      if (patient.birthDate != null)
        (Icons.cake_outlined, 'Naissance', _formatDate(patient.birthDate!)),
      if (patient.phone != null && patient.phone!.isNotEmpty)
        (Icons.phone_outlined, 'Téléphone', patient.phone!),
      if (patient.email != null && patient.email!.isNotEmpty)
        (Icons.mail_outline, 'Email', patient.email!),
      if (patient.socialSecurityNumber != null &&
          patient.socialSecurityNumber!.isNotEmpty)
        (
          Icons.badge_outlined,
          'N° sécurité sociale',
          patient.socialSecurityNumber!
        ),
      if (patient.lastVisitAt != null)
        (Icons.history, 'Dernière visite', _formatDate(patient.lastVisitAt!)),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: tokens.borderSubtle)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PatientSheetAlertsBanner(alerts: _alerts, error: _alertsError),
            Row(
              children: [
                NubiaAvatar(
                  initials: NubiaInitials.of(patient.fullName),
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    patient.fullName,
                    style: textTheme.titleLarge?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('patient_sheet_close'),
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: 16),
            NubiaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(rows[i].$1, size: 20, color: cs.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rows[i].$2,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                rows[i].$3,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (rows.isEmpty)
                    Text(
                      'Aucune information administrative disponible.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const _PatientSheetSectionsSkeleton()
            else ...[
              PatientBalanceSection(
                patient: _patientDetail,
                error: _balanceError,
              ),
              const SizedBox(height: 16),
              PatientTagsSection(
                patientId: patient.id,
                initialTags: _tags,
                initialError: _tagsError,
              ),
              const SizedBox(height: 16),
              PatientDocumentsSection(
                documents: _documents,
                error: _documentsError,
              ),
            ],
            const SizedBox(height: 16),
            const _PatientSheetConfidentialityNotice(),
          ],
        ),
      ),
    );
  }
}

/// Bloc d'alertes en tête de fiche (design-v2, #5114) : alimenté par le
/// chargement unique de [_PatientSheetState] via `ListPatientAlertsUseCase`
/// — distinct des pastilles de la colonne « Alertes & étiquettes » de la
/// liste (`PatientAlertBadge`, #5113), qui lisent leurs propres champs déjà
/// présents sur `CabinetPatient` sans appeler ce use case. Le détail de
/// chaque alerte s'affiche en clair (une puce par alerte) au lieu d'un
/// tooltip sur une icône (note #2 de la maquette). Best-effort
/// (#4093/#4094) : un échec n'empêche pas de consulter le reste de la
/// fiche, mais devient visible au lieu d'un `SizedBox.shrink()` silencieux.
/// Cloisonnement : `PatientAlert.message` ne contient que du texte
/// administratif, zéro donnée clinique.
class _PatientSheetAlertsBanner extends StatelessWidget {
  const _PatientSheetAlertsBanner({required this.alerts, required this.error});

  final List<PatientAlert>? alerts;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          key: const Key('patient_sheet_alerts_error'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.dangerBg,
            border: Border.all(color: NubiaColors.dangerBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.error, color: tokens.dangerFg, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Alertes accueil indisponibles.',
                  style: textTheme.bodyMedium?.copyWith(color: tokens.dangerFg),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final list = alerts ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        key: const Key('patient_sheet_alerts_banner'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.dangerBg,
          border: Border.all(color: NubiaColors.dangerBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: tokens.dangerFg, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${list.length} alerte${list.length > 1 ? 's' : ''}'
                    ' accueil',
                    style: textTheme.titleSmall?.copyWith(
                      color: tokens.dangerFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final alert in list)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style:
                          textTheme.bodyMedium?.copyWith(color: tokens.dangerFg),
                    ),
                    Expanded(
                      child: Text(
                        alert.message,
                        style: textTheme.bodyMedium
                            ?.copyWith(color: tokens.dangerFg),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton du chargement unique de la fiche (design-v2, #5115) : un seul
/// bloc pour les 3 sections dépendantes du fetch consolidé (solde,
/// étiquettes, documents) — remplace les 3 skeletons indépendants qui
/// apparaissaient et disparaissaient chacun à son rythme.
class _PatientSheetSectionsSkeleton extends StatelessWidget {
  const _PatientSheetSectionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: Key('patient_sheet_sections_loading'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NubiaSkeletonLoader(height: 20, borderRadius: 4),
        SizedBox(height: 16),
        NubiaSkeletonLoader(height: 32, borderRadius: 16),
        SizedBox(height: 16),
        NubiaSkeletonLoader(height: 48, borderRadius: 8),
      ],
    );
  }
}

/// Bandeau de cloisonnement en bas de fiche (design-v2, note #9) : la
/// mention passait jusqu'ici par les seuls commentaires de code (lignes
/// 16-19, 174-175, 272) — elle passe désormais à l'écran, avec le cas
/// ambigu des étiquettes (#4041) explicité : une étiquette comme « AVK »
/// est une consigne d'accueil saisie par le cabinet, pas un élément du
/// dossier médical.
class _PatientSheetConfidentialityNotice extends StatelessWidget {
  const _PatientSheetConfidentialityNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('patient_sheet_confidentiality_notice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NubiaColors.n50,
        border: Border.all(color: NubiaColors.n200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield, size: 18, color: NubiaColors.n500),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cloisonnement secrétariat : aucune donnée clinique. Les '
              "étiquettes sont administratives — « AVK » est ici une "
              "consigne d'accueil saisie par le cabinet, pas un élément "
              'du dossier médical.',
              style: TextStyle(fontSize: 11.5, color: NubiaColors.n600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Solde restant dû du patient (US-4.6.2, #4044/#4045) — présentation pure :
/// [patient] et [error] proviennent du chargement unique de la fiche
/// (`_PatientSheetState._load`, design-v2 #5115), la liste (`PatientsLoaded`)
/// n'exposant pas `balanceDueCents` (seul le détail
/// `GET /cabinet/patients/:id` le renvoie). Best-effort : une fiche patient
/// reste consultable même si le solde ne charge pas, mais l'échec est
/// désormais visible — fini le `SizedBox.shrink()` silencieux.
class PatientBalanceSection extends StatelessWidget {
  const PatientBalanceSection({
    super.key,
    required this.patient,
    required this.error,
  });

  /// Détail patient déjà chargé par la fiche, `null` si [error] est défini.
  final CabinetPatient? patient;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (error != null) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Solde indisponible : $error',
              key: const Key('patient_balance_error'),
              style: TextStyle(color: cs.error),
            ),
          ),
        ],
      );
    }
    final cents = patient?.balanceDueCents ?? 0;
    final noShowCount = patient?.noShowCount;
    final guardians = patient?.guardians ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Text(
              'Solde : ${NubiaMoney.formatCents(cents)}',
              key: const Key('patient_balance'),
              style: cents > 0
                  ? TextStyle(color: cs.error, fontWeight: FontWeight.w600)
                  : null,
            ),
          ],
        ),
        if (noShowCount != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.person_off_outlined,
                  size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                'Rendez-vous manqués : $noShowCount',
                key: const Key('patient_no_show_count'),
                style: noShowCount > 0
                    ? TextStyle(color: cs.error, fontWeight: FontWeight.w600)
                    : null,
              ),
            ],
          ),
        ],
        if (guardians.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                'Tuteur : ${guardians.map((g) => g.fullName).join(', ')}',
                key: const Key('patient_guardians'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Étiquettes administratives du patient (#4041) — chargement, ajout,
/// suppression. Distinct du journal clinique : zéro donnée de santé.
///
/// design-v2 (#5115) : [initialTags]/[initialError] viennent du chargement
/// unique de la fiche (`_PatientSheetState._load`) — plus de fetch au
/// montage. Un rechargement ([_reload]) reste local à cette section : il
/// n'a lieu qu'après une mutation (ajout/suppression), pas à l'ouverture.
class PatientTagsSection extends StatefulWidget {
  const PatientTagsSection({
    super.key,
    required this.patientId,
    required this.initialTags,
    required this.initialError,
  });

  final String patientId;
  final List<PatientTag>? initialTags;
  final String? initialError;

  @override
  State<PatientTagsSection> createState() => _PatientTagsSectionState();
}

class _PatientTagsSectionState extends State<PatientTagsSection> {
  List<PatientTag>? _tags;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _tags = widget.initialTags;
    _error = widget.initialError;
  }

  /// Recharge après une mutation (ajout/suppression) — le chargement
  /// initial, lui, est fait une seule fois par `_PatientSheetState` (#5115).
  Future<void> _reload() async {
    final result =
        await GetIt.instance<ListPatientTagsUseCase>()(widget.patientId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() => _error = failure.message),
      (tags) => setState(() {
        _tags = tags;
        _error = null;
      }),
    );
  }

  Future<void> _addTag(String label) async {
    setState(() => _submitting = true);
    final result = await GetIt.instance<CreatePatientTagUseCase>()(
      widget.patientId,
      label: label,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => _reload(),
    );
  }

  Future<void> _removeTag(String tagId) async {
    final result = await GetIt.instance<DeletePatientTagUseCase>()(
      widget.patientId,
      tagId,
    );
    if (!mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => _reload(),
    );
  }

  Future<void> _openAddDialog() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle étiquette'),
        content: NubiaTextField(
          key: const Key('patient_tag_label_field'),
          controller: controller,
          label: 'Libellé',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const Key('patient_tag_dialog_confirm'),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (label != null && label.isNotEmpty) {
      await _addTag(label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tags = _tags;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Étiquettes', style: textTheme.titleSmall),
            const Spacer(),
            IconButton(
              key: const Key('patient_tags_add_button'),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              tooltip: 'Ajouter une étiquette',
              onPressed: _submitting ? null : _openAddDialog,
            ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: cs.error))
        else if (tags == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: NubiaSkeletonLoader(height: 32, borderRadius: 16),
          )
        else if (tags.isEmpty)
          Text(
            'Aucune étiquette.',
            key: const Key('patient_tags_empty'),
            style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          Wrap(
            key: const Key('patient_tags_wrap'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in tags)
                NubiaChip(
                  key: Key('patient_tag_${tag.id}'),
                  label: tag.label,
                  variant: NubiaChipVariant.input,
                  onRemove: () => _removeTag(tag.id),
                ),
            ],
          ),
      ],
    );
  }
}

/// Documents du dossier patient (GED, §4.4, #4042) — liste vide/remplie.
/// Upload hors scope ici : `POST .../documents` déjà exposé côté API,
/// reste à câbler dans un futur écran dédié si besoin.
///
/// design-v2 (#5115) : présentation pure — [documents]/[error] viennent du
/// chargement unique de la fiche (`_PatientSheetState._load`), plus de
/// fetch dédié ni de skeleton local.
class PatientDocumentsSection extends StatelessWidget {
  const PatientDocumentsSection({
    super.key,
    required this.documents,
    required this.error,
  });

  final List<PatientDocument>? documents;
  final String? error;

  IconData _iconFor(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} Ko';
    return '${(kb / 1024).toStringAsFixed(1)} Mo';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final docs = documents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Documents', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        if (error != null)
          Text(
            'Documents indisponibles : $error',
            key: const Key('patient_documents_error'),
            style: TextStyle(color: cs.error),
          )
        else if (docs == null || docs.isEmpty)
          Text(
            'Aucun document.',
            key: const Key('patient_documents_empty'),
            style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          Column(
            key: const Key('patient_documents_list'),
            children: [
              for (final doc in docs)
                ListRow(
                  key: Key('patient_document_${doc.id}'),
                  leading: Icon(_iconFor(doc.mimeType), color: cs.primary),
                  title: doc.filename,
                  subtitle: '${doc.category} · ${_formatSize(doc.sizeBytes)}',
                ),
            ],
          ),
      ],
    );
  }
}

/// Skeleton de chargement de la liste patients (barre de recherche + lignes).
class _PatientsSkeleton extends StatelessWidget {
  const _PatientsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('patients_loading'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        const NubiaSkeletonLoader(height: 48, borderRadius: 8),
        const SizedBox(height: 16),
        for (var i = 0; i < 8; i++) ...[
          const NubiaSkeletonLoader(height: 56, borderRadius: 12),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
