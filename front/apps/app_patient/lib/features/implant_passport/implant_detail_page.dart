import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:share_plus/share_plus.dart';

import 'implant_detail_cubit.dart';

/// Détail d'un implant du passeport implantaire (#5334) — export et partage
/// scopés à CET implant, lecture seule (aucune action de modification).
class ImplantDetailPage extends StatelessWidget {
  final ImplantItem implant;
  const ImplantDetailPage({super.key, required this.implant});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<ImplantDetailCubit>(),
      child: Scaffold(
        appBar: AppBar(title: Text(implant.brand)),
        body: _ImplantDetailBody(implant: implant),
      ),
    );
  }
}

class _ImplantDetailBody extends StatelessWidget {
  final ImplantItem implant;
  const _ImplantDetailBody({required this.implant});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ImplantDetailCubit, ImplantDetailState>(
      listenWhen: (_, curr) =>
          curr is ImplantDetailError || curr is ImplantDetailUrlReady,
      listener: (context, state) {
        if (state is ImplantDetailError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
          return;
        }
        if (state is ImplantDetailUrlReady) {
          if (state.action == ImplantDetailAction.share) {
            Share.share(
              state.url,
              subject: 'Passeport implantaire · ${implant.brand}',
            );
          } else {
            openDocumentUrl(state.url).then((opened) {
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Impossible d'ouvrir l'export.")),
                );
              }
            });
          }
          // Repasse par un état neutre pour éviter de rouvrir le lien / de
          // relancer le partage à chaque rebuild (même piège que
          // ImplantPassportCubit.export(), cf. #4142).
          context.read<ImplantDetailCubit>().reset();
        }
      },
      builder: (context, state) {
        final exporting =
            state is ImplantDetailLoading && state.action == ImplantDetailAction.export;
        final sharing =
            state is ImplantDetailLoading && state.action == ImplantDetailAction.share;
        final busy = exporting || sharing;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                key: Key('implant_detail_${implant.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.medical_information_outlined),
                title: Text(implant.brand),
                subtitle: Text([
                  if (implant.toothPosition != null)
                    'Position ${implant.toothPosition}',
                  if (implant.placementDate != null)
                    'Posé le ${implant.placementDate}',
                  if (implant.lotNumber != null) 'Lot ${implant.lotNumber}',
                ].join(' · ')),
              ),
              if (implant.placementDate != null ||
                  implant.practitioner != null ||
                  implant.office != null ||
                  implant.prosthesis != null) ...[
                const SizedBox(height: 16),
                _PlacementCard(implant: implant),
              ],
              if (implant.lastControlDate != null ||
                  implant.nextControl != null) ...[
                const SizedBox(height: 16),
                _FollowUpCard(implant: implant),
              ],
              const SizedBox(height: 24),
              NubiaButton(
                key: const Key('implant_detail_export_button'),
                label: 'Exporter cette fiche',
                icon: Icons.picture_as_pdf,
                isLoading: exporting,
                onPressed: busy
                    ? null
                    : () => context.read<ImplantDetailCubit>().exportImplant(implant.id),
              ),
              const SizedBox(height: 12),
              NubiaButton(
                key: const Key('implant_detail_share_button'),
                label: 'Partager avec un professionnel',
                icon: Icons.share,
                variant: NubiaButtonVariant.secondary,
                isLoading: sharing,
                onPressed: busy
                    ? null
                    : () => context.read<ImplantDetailCubit>().shareImplant(implant.id),
              ),
              const SizedBox(height: 16),
              const _ReadOnlyNotice(),
            ],
          ),
        );
      },
    );
  }
}

/// Bloc « Pose » : date, praticien, cabinet et prothèse posée (#5332).
/// Chaque ligne ne s'affiche que si la donnée correspondante est renseignée.
class _PlacementCard extends StatelessWidget {
  const _PlacementCard({required this.implant});

  final ImplantItem implant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placementDate = implant.placementDate;
    final practitioner = implant.practitioner;
    final office = implant.office;
    final prosthesis = implant.prosthesis;

    return NubiaCard(
      key: const Key('implant_detail_placement_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medical_services, color: NubiaColors.brand700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Pose',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (placementDate != null) ...[
            const SizedBox(height: 12),
            _FollowUpRow(
              label: 'Date',
              value: NubiaDate.dayLong(placementDate),
            ),
          ],
          if (practitioner != null) ...[
            const SizedBox(height: 8),
            _FollowUpRow(label: 'Praticien', value: practitioner),
          ],
          if (office != null) ...[
            const SizedBox(height: 8),
            _FollowUpRow(label: 'Cabinet', value: office),
          ],
          if (prosthesis != null) ...[
            const SizedBox(height: 8),
            _FollowUpRow(label: 'Prothèse', value: prosthesis),
          ],
        ],
      ),
    );
  }
}

/// Bloc « Suivi recommandé » : dernier contrôle et prochain rendez-vous
/// (#5333). Chaque ligne ne s'affiche que si la donnée correspondante est
/// renseignée.
class _FollowUpCard extends StatelessWidget {
  const _FollowUpCard({required this.implant});

  final ImplantItem implant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastControlDate = implant.lastControlDate;
    final nextControl = implant.nextControl;

    return NubiaCard(
      key: const Key('implant_detail_follow_up_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_repeat, color: NubiaColors.brand700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Suivi recommandé',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (lastControlDate != null) ...[
            const SizedBox(height: 12),
            _FollowUpRow(
              label: 'Dernier contrôle',
              value: NubiaDate.dayLong(lastControlDate),
            ),
          ],
          if (nextControl != null) ...[
            const SizedBox(height: 8),
            _FollowUpRow(
              label: 'Prochain',
              value: nextControl,
              valueColor: NubiaColors.brand700,
            ),
          ],
        ],
      ),
    );
  }
}

class _FollowUpRow extends StatelessWidget {
  const _FollowUpRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: valueColor ?? cs.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      key: const Key('implant_detail_readonly_notice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.neutralBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock, size: 18, color: tokens.neutralFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ces informations viennent de votre dossier médical. '
              'Seul votre praticien peut les modifier.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.neutralFg),
            ),
          ),
        ],
      ),
    );
  }
}
