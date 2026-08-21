import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'implant_passport_cubit.dart';

class ImplantPassportPage extends StatelessWidget {
  const ImplantPassportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<ImplantPassportCubit>()..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Passeport implantaire')),
        body: const _ImplantPassportBody(),
      ),
    );
  }
}

class _ImplantPassportBody extends StatelessWidget {
  const _ImplantPassportBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ImplantPassportCubit, ImplantPassportState>(
      listenWhen: (_, s) =>
          s is ImplantPassportLoaded && s.exportUrl != null,
      listener: (context, state) {
        if (state is ImplantPassportLoaded && state.exportUrl != null) {
          openDocumentUrl(state.exportUrl!).then((opened) {
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Impossible d'ouvrir l'export.")),
              );
            }
          });
          // Repasse par un état sans exportUrl pour éviter de rouvrir le
          // lien à chaque rebuild.
          context.read<ImplantPassportCubit>().load();
        }
      },
      builder: (context, state) {
        if (state is ImplantPassportLoading) {
          return const _ImplantPassportSkeleton();
        }
        if (state is ImplantPassportError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () => context.read<ImplantPassportCubit>().load(),
          );
        }
        if (state is ImplantPassportLoaded) {
          return Column(
            children: [
              Expanded(
                child: state.implants.isEmpty
                    ? const NubiaEmptyState(
                        key: Key('implant_passport_empty'),
                        icon: Icons.medical_information_outlined,
                        title: 'Aucun implant enregistré',
                      )
                    : ListView.separated(
                        key: const Key('implant_passport_list'),
                        padding: const EdgeInsets.all(16),
                        itemCount: state.implants.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final theme = Theme.of(context);
                          final implant = state.implants[index];
                          final toothPosition = implant.toothPosition;
                          final anatomicalName =
                              toothLabelFromFdi(toothPosition);
                          final manufacturerModel = [
                            if (implant.manufacturer != null)
                              implant.manufacturer!,
                            if (implant.model != null) implant.model!,
                          ].join(' · ');
                          final infoRows = <Widget>[
                            if (implant.placementDate != null)
                              _ImplantInfoRow(
                                label: 'Posé le',
                                value: NubiaDate.dayLong(
                                    implant.placementDate!),
                              ),
                            if (implant.lotNumber != null)
                              _ImplantInfoRow(
                                label: 'N° de lot',
                                value: implant.lotNumber!,
                                monospace: true,
                              ),
                            if (implant.practitioner != null)
                              _ImplantInfoRow(
                                label: 'Praticien',
                                value: implant.practitioner!,
                              ),
                          ];
                          return NubiaCard(
                            key: Key('implant_${implant.id}'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if (toothPosition != null &&
                                        anatomicalName != null)
                                      Container(
                                        width: 56,
                                        height: 56,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: NubiaColors.brand50,
                                          border: Border.all(
                                              color: NubiaColors.brand100),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              toothPosition,
                                              style: theme
                                                  .textTheme.titleMedium
                                                  ?.copyWith(
                                                color: NubiaColors.brand800,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              'FDI',
                                              style: theme
                                                  .textTheme.labelSmall
                                                  ?.copyWith(
                                                color: NubiaColors.brand700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      const Icon(Icons
                                          .medical_information_outlined),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            anatomicalName ?? implant.brand,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w600),
                                          ),
                                          if (manufacturerModel.isNotEmpty)
                                            Text(
                                              manufacturerModel,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                      color:
                                                          NubiaColors.n500),
                                            ),
                                          if (infoRows.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 4),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: infoRows,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                InkWell(
                                  key: Key(
                                      'implant_detail_link_${implant.id}'),
                                  onTap: () => context.push(
                                    '/implant-passport/${implant.id}',
                                    extra: implant,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Voir la fiche complète',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                                color: NubiaColors.brand700),
                                      ),
                                      const Icon(Icons.chevron_right,
                                          color: NubiaColors.brand700),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ExportPassportCard(
                      implantCount: state.implants.length,
                      onExport: () =>
                          context.read<ImplantPassportCubit>().export(),
                    ),
                    const SizedBox(height: 12),
                    const _LegalTraceabilityNotice(),
                  ],
                ),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Ligne clé/valeur d'une carte d'implant (#5320) : remplace l'ancien
/// sous-titre `[...].join(' · ')`, où le n° de lot se lisait au milieu
/// d'une phrase au lieu d'être isolé pour un rappel de lot.
class _ImplantInfoRow extends StatelessWidget {
  const _ImplantInfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: NubiaColors.n500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: NubiaColors.n900,
                fontWeight: FontWeight.w500,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Squelette de chargement préfigurant la liste de cartes d'implants
/// (mêmes gabarits vignette + lignes que `implant_passport_list`).
class _ImplantPassportSkeleton extends StatelessWidget {
  const _ImplantPassportSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('implant_passport_loading'),
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const _ImplantSkeletonCard(),
    );
  }
}

class _ImplantSkeletonCard extends StatelessWidget {
  const _ImplantSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NubiaSkeletonLoader(height: 40, width: 40, borderRadius: 10),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NubiaSkeletonLoader(height: 14, width: 180),
                    SizedBox(height: 8),
                    NubiaSkeletonLoader(height: 12, width: 120),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: NubiaSkeletonLoader(height: 12, width: 140),
          ),
        ],
      ),
    );
  }
}

/// Carte « Emporter mon passeport » : explique le contenu du PDF d'export
/// global avant le bouton, avec le décompte réel d'implants (#5326).
class _ExportPassportCard extends StatelessWidget {
  const _ExportPassportCard({
    required this.implantCount,
    required this.onExport,
  });

  final int implantCount;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NubiaCard(
      key: const Key('implant_passport_export_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Emporter mon passeport',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _exportDescription(implantCount),
            style:
                theme.textTheme.bodyMedium?.copyWith(color: NubiaColors.n600),
          ),
          const SizedBox(height: 16),
          NubiaButton(
            key: const Key('implant_passport_export_button'),
            label: 'Exporter en PDF',
            icon: Icons.picture_as_pdf,
            onPressed: onExport,
          ),
        ],
      ),
    );
  }
}

const _kImplantCountWords = {
  2: 'deux',
  3: 'trois',
  4: 'quatre',
  5: 'cinq',
  6: 'six',
  7: 'sept',
  8: 'huit',
  9: 'neuf',
  10: 'dix',
};

String _exportDescription(int implantCount) {
  if (implantCount == 1) {
    return 'Un PDF officiel reprenant votre implant, sa référence et son '
        'numéro de lot.';
  }
  if (implantCount <= 0) {
    return 'Un PDF officiel reprenant vos implants, leurs références et '
        'leurs numéros de lot.';
  }
  final word = _kImplantCountWords[implantCount] ?? '$implantCount';
  return 'Un PDF officiel reprenant vos $word implants, leurs références '
      'et leurs numéros de lot.';
}

/// Bandeau légal rappelant l'obligation de traçabilité des dispositifs
/// médicaux implantables (#5326).
class _LegalTraceabilityNotice extends StatelessWidget {
  const _LegalTraceabilityNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;

    return Container(
      key: const Key('implant_passport_legal_notice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.neutralBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user, size: 18, color: tokens.neutralFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'La traçabilité des dispositifs médicaux implantables est '
              'une obligation légale : votre praticien conserve ces '
              'informations, et vous en avez une copie permanente.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: tokens.neutralFg),
            ),
          ),
        ],
      ),
    );
  }
}
