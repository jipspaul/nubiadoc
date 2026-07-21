//! Section fiche patient : questionnaire médical soumis en attente de
//! validation (#4110). Suite à `GET .../medical-questionnaire` (#4108, RLS
//! masque déjà les brouillons) — n'affiche que les soumissions `submitted`
//! (pas encore `reviewed`).
//!
//! Le bouton "Valider et importer" ouvre une confirmation avant d'appeler
//! `POST .../medical-questionnaire/review` : c'est cette confirmation qui
//! constitue la revue humaine obligatoire exigée par l'issue — jamais
//! d'import automatique silencieux au chargement de la fiche.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

class MedicalQuestionnaireReviewSection extends StatefulWidget {
  const MedicalQuestionnaireReviewSection({super.key, required this.patientId});

  final String patientId;

  @override
  State<MedicalQuestionnaireReviewSection> createState() =>
      _MedicalQuestionnaireReviewSectionState();
}

class _MedicalQuestionnaireReviewSectionState
    extends State<MedicalQuestionnaireReviewSection> {
  MedicalQuestionnaire? _submission;
  bool _loading = true;
  bool _reviewing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result =
        await GetIt.instance<GetCabinetMedicalQuestionnaireUseCase>()(
      widget.patientId,
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
      }),
      (submission) => setState(() {
        _submission = submission;
        _error = null;
        _loading = false;
      }),
    );
  }

  Future<void> _confirmAndReview() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Valider et importer ?'),
        content: const Text(
          'Le contenu du questionnaire sera ajouté au dossier médical '
          '(antécédents, allergies, traitements, ALD). Cette action est '
          'irréversible.',
        ),
        actions: [
          TextButton(
            key: const Key('questionnaire_review_dialog_cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('questionnaire_review_dialog_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Valider et importer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _reviewing = true);
    final result = await GetIt.instance<ReviewMedicalQuestionnaireUseCase>()(
      widget.patientId,
    );
    if (!mounted) return;
    setState(() => _reviewing = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
      (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Questionnaire importé au dossier médical.')),
        );
        _load();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final submission = _submission;
    final pending = submission != null && submission.status == 'submitted';

    return NubiaCard(
      key: const Key('medical_questionnaire_review_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Questionnaire médical',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!, style: TextStyle(color: cs.error))
          else if (_loading)
            const NubiaSkeletonLoader(height: 48, borderRadius: 8)
          else if (!pending)
            Text(
              'Aucun questionnaire en attente de validation.',
              key: const Key('medical_questionnaire_review_empty'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            )
          else ...[
            ListRow(
              key: const Key('medical_questionnaire_review_pending'),
              leading: Icon(Icons.assignment_late_outlined, color: cs.primary),
              title: 'Questionnaire soumis par le patient',
              subtitle: _preview(submission.payload),
            ),
            const SizedBox(height: 12),
            NubiaButton(
              key: const Key('medical_questionnaire_review_button'),
              label: 'Valider et importer',
              icon: Icons.check_circle_outline,
              isLoading: _reviewing,
              onPressed: _reviewing ? null : _confirmAndReview,
            ),
          ],
        ],
      ),
    );
  }

  String _preview(Map<String, dynamic> payload) {
    final parts = <String>[];
    final antecedents = payload['antecedents'] as String?;
    final allergies = payload['allergies'] as String?;
    final traitements = payload['traitements_en_cours'] as String?;
    final ald = payload['ald'] == true;
    if (antecedents != null && antecedents.isNotEmpty) {
      parts.add('Antécédents : $antecedents');
    }
    if (allergies != null && allergies.isNotEmpty) {
      parts.add('Allergies : $allergies');
    }
    if (traitements != null && traitements.isNotEmpty) {
      parts.add('Traitements : $traitements');
    }
    if (ald) parts.add('ALD déclarée');
    return parts.isEmpty ? 'Aucun détail renseigné.' : parts.join(' · ');
  }
}
