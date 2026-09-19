import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'consent_templates_bloc.dart';
import 'consent_templates_event.dart';
import 'consent_templates_state.dart';
import 'widgets/consent_template_form_dialog.dart';
import 'widgets/consent_templates_list.dart';

/// Écran « Modèles de consentement » (#7198, DP-F6.c) : catalogue global en
/// lecture, modèles du cabinet créés/édités depuis cet écran, aperçu du
/// texte avant sélection depuis un devis.
///
/// Doit être placée sous un [BlocProvider<ConsentTemplatesBloc>].
class ConsentTemplatesPage extends StatefulWidget {
  const ConsentTemplatesPage({super.key});

  @override
  State<ConsentTemplatesPage> createState() => _ConsentTemplatesPageState();
}

class _ConsentTemplatesPageState extends State<ConsentTemplatesPage> {
  @override
  void initState() {
    super.initState();
    context
        .read<ConsentTemplatesBloc>()
        .add(const ConsentTemplatesLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('consent_templates_scaffold'),
      appBar: AppBar(
        title: const Text('Modèles de consentement'),
        actions: [
          BlocBuilder<ConsentTemplatesBloc, ConsentTemplatesState>(
            builder: (context, state) {
              final loaded = state is ConsentTemplatesLoaded ? state : null;
              return IconButton(
                key: const Key('consent_templates_create_button'),
                icon: const Icon(Icons.add),
                tooltip: 'Nouveau modèle',
                onPressed: loaded == null || loaded.actionInProgress
                    ? null
                    : () => _onCreate(context),
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<ConsentTemplatesBloc, ConsentTemplatesState>(
        listenWhen: (previous, current) =>
            current is ConsentTemplatesLoaded && current.actionError != null,
        listener: (context, state) {
          final message = (state as ConsentTemplatesLoaded).actionError!;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              key: const Key('consent_templates_error_snackbar'),
              content: Text(message),
            ));
        },
        builder: (context, state) {
          if (state is ConsentTemplatesError) {
            return NubiaErrorWidget(
              key: const Key('consent_templates_error'),
              message: state.message,
              onRetry: () => context
                  .read<ConsentTemplatesBloc>()
                  .add(const ConsentTemplatesLoadRequested()),
            );
          }
          if (state is! ConsentTemplatesLoaded) {
            return const NubiaSkeletonLoader(
              key: Key('consent_templates_loading'),
              height: 120,
              borderRadius: 12,
            );
          }
          return ConsentTemplatesList(
            templates: state.templates,
            onEdit: (template) => _onEdit(context, template),
          );
        },
      ),
    );
  }

  Future<void> _onCreate(BuildContext context) async {
    final bloc = context.read<ConsentTemplatesBloc>();
    final result = await showConsentTemplateFormDialog(context);
    if (result == null) return;
    bloc.add(ConsentTemplatesCreateRequested(
      actCategory: result.actCategory,
      title: result.title,
      bodyMarkdown: result.bodyMarkdown,
    ));
  }

  Future<void> _onEdit(BuildContext context, ConsentTemplate template) async {
    final bloc = context.read<ConsentTemplatesBloc>();
    final result = await showConsentTemplateFormDialog(
      context,
      initial: template,
    );
    if (result == null) return;
    bloc.add(ConsentTemplatesUpdateRequested(
      id: template.id,
      actCategory: result.actCategory,
      title: result.title,
      bodyMarkdown: result.bodyMarkdown,
    ));
  }
}
