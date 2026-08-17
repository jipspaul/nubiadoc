import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'implant_detail_page.dart';
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
          s is ImplantPassportError ||
          (s is ImplantPassportLoaded && s.exportUrl != null),
      listener: (context, state) {
        if (state is ImplantPassportError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
          return;
        }
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
          return const Center(child: CircularProgressIndicator());
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
                    : ListView(
                        key: const Key('implant_passport_list'),
                        children: [
                          for (final implant in state.implants)
                            ListTile(
                              key: Key('implant_${implant.id}'),
                              leading: const Icon(
                                  Icons.medical_information_outlined),
                              title: Text(implant.brand),
                              subtitle: Text([
                                if (implant.toothPosition != null)
                                  'Position ${implant.toothPosition}',
                                if (implant.placementDate != null)
                                  'Posé le ${implant.placementDate}',
                                if (implant.lotNumber != null)
                                  'Lot ${implant.lotNumber}',
                              ].join(' · ')),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ImplantDetailPage(implant: implant),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: NubiaButton(
                    key: const Key('implant_passport_export_button'),
                    label: 'Exporter en PDF',
                    icon: Icons.picture_as_pdf_outlined,
                    onPressed: () =>
                        context.read<ImplantPassportCubit>().export(),
                  ),
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
