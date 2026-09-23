import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'questionnaire_templates_bloc.dart';
import 'questionnaire_templates_event.dart';
import 'questionnaire_templates_state.dart';
import 'widgets/questionnaire_template_editor_page.dart';
import 'widgets/questionnaire_templates_list.dart';

/// Écran « Modèle de questionnaire médical » (#7158) : catalogue global en
/// lecture, modèle propre au cabinet créé/édité depuis cet écran.
///
/// Doit être placée sous un [BlocProvider<QuestionnaireTemplatesBloc>].
class QuestionnaireTemplatesPage extends StatefulWidget {
  const QuestionnaireTemplatesPage({super.key});

  @override
  State<QuestionnaireTemplatesPage> createState() =>
      _QuestionnaireTemplatesPageState();
}

class _QuestionnaireTemplatesPageState
    extends State<QuestionnaireTemplatesPage> {
  @override
  void initState() {
    super.initState();
    context
        .read<QuestionnaireTemplatesBloc>()
        .add(const QuestionnaireTemplatesLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('questionnaire_templates_scaffold'),
      appBar: AppBar(title: const Text('Questionnaire médical')),
      body: BlocConsumer<QuestionnaireTemplatesBloc, QuestionnaireTemplatesState>(
        listenWhen: (previous, current) =>
            current is QuestionnaireTemplatesLoaded &&
            current.actionError != null,
        listener: (context, state) {
          final message = (state as QuestionnaireTemplatesLoaded).actionError!;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              key: const Key('questionnaire_templates_error_snackbar'),
              content: Text(message),
            ));
        },
        builder: (context, state) {
          if (state is QuestionnaireTemplatesError) {
            return NubiaErrorWidget(
              key: const Key('questionnaire_templates_error'),
              message: state.message,
              onRetry: () => context
                  .read<QuestionnaireTemplatesBloc>()
                  .add(const QuestionnaireTemplatesLoadRequested()),
            );
          }
          if (state is! QuestionnaireTemplatesLoaded) {
            return const NubiaSkeletonLoader(
              key: Key('questionnaire_templates_loading'),
              height: 120,
              borderRadius: 12,
            );
          }
          return QuestionnaireTemplatesList(
            cabinetTemplate: state.cabinetTemplate,
            globalTemplates: state.globalTemplates,
            onEditCabinetTemplate: (template) => _onEdit(context, template),
            onCreateCabinetTemplate: () => _onCreate(context),
          );
        },
      ),
    );
  }

  Future<void> _onCreate(BuildContext context) async {
    final bloc = context.read<QuestionnaireTemplatesBloc>();
    final result = await showQuestionnaireTemplateEditor(context);
    if (result == null) return;
    bloc.add(QuestionnaireTemplatesCreateRequested(
      title: result.title,
      schema: result.schema,
    ));
  }

  Future<void> _onEdit(
    BuildContext context,
    QuestionnaireTemplate template,
  ) async {
    final bloc = context.read<QuestionnaireTemplatesBloc>();
    final result =
        await showQuestionnaireTemplateEditor(context, initial: template);
    if (result == null) return;
    bloc.add(QuestionnaireTemplatesUpdateRequested(
      id: template.id,
      title: result.title,
      schema: result.schema,
    ));
  }
}
