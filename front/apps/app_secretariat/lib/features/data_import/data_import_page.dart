import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Écran « Reprise de données » (#7178, DP-F14.c) : choix du type, upload,
/// résultat de l'analyse à blanc (lignes OK / en erreur avec motif),
/// lancement, progression, rapport final téléchargeable. Pas de bloc ici
/// (parcours séquentiel ponctuel) : use cases injectés via `GetIt`, même
/// convention que `stock_import_page.dart` (#7182/#7183).
class DataImportPage extends StatefulWidget {
  const DataImportPage({super.key});

  @override
  State<DataImportPage> createState() => _DataImportPageState();
}

class _DataImportPageState extends State<DataImportPage> {
  DataImportKind _kind = DataImportKind.csvPatients;
  PickedFile? _file;
  bool _uploading = false;
  bool _dryRunning = false;
  bool _running = false;
  String? _error;
  DataImportJob? _job;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await GetIt.instance<FilePickerService>()
        .pickFile(allowedExtensions: ['csv']);
    if (file == null || !mounted) return;
    setState(() {
      _file = file;
      _error = null;
    });
  }

  Future<void> _onUpload() async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    final result = await GetIt.instance<UploadDataImportUseCase>()(
      kind: _kind,
      bytes: file.bytes,
      filename: file.name,
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _uploading = false;
        _error = failure.message;
      }),
      (job) => setState(() {
        _uploading = false;
        _file = null;
        _job = job;
      }),
    );
  }

  Future<void> _onDryRun() async {
    final job = _job;
    if (job == null) return;
    setState(() {
      _dryRunning = true;
      _error = null;
    });
    final result = await GetIt.instance<DryRunDataImportUseCase>()(job.id);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _dryRunning = false;
        _error = failure.message;
      }),
      (updated) => setState(() {
        _dryRunning = false;
        _job = updated;
      }),
    );
  }

  Future<void> _onRun() async {
    final job = _job;
    if (job == null) return;
    setState(() {
      _running = true;
      _error = null;
    });
    // Le run est synchrone côté API (transaction unique) : le polling ici
    // rafraîchit surtout l'écran en cas de rechargement pendant l'attente
    // (#7178, procédure « écran + polling du statut »).
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      GetIt.instance<GetDataImportStatusUseCase>()(job.id).then((result) {
        if (!mounted) return;
        result.fold((_) {}, (updated) => setState(() => _job = updated));
      });
    });
    final result = await GetIt.instance<RunDataImportUseCase>()(job.id);
    _pollTimer?.cancel();
    if (!mounted) return;
    setState(() => _running = false);
    result.fold(
      (failure) => setState(() => _error = failure.message),
      (updated) => setState(() => _job = updated),
    );
  }

  Future<void> _onDownloadReport() async {
    final job = _job;
    if (job == null) return;
    final report = <String, dynamic>{
      'job_id': job.id,
      'status': job.status.name,
      'total_count': job.totalCount,
      'imported_count': job.importedCount,
      'skipped_count': job.skippedCount,
      'error_count': job.errorCount,
      'lines': [
        for (final line in job.report.lines)
          {
            'line': line.line,
            if (line.externalRef != null) 'external_ref': line.externalRef,
            'action': line.action,
            if (line.message != null) 'message': line.message,
          },
      ],
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(report)));
    await GetIt.instance<FilePickerService>().saveFile(
      bytes: bytes,
      fileName: 'rapport-import-${job.id}.json',
    );
  }

  void _reset() {
    setState(() {
      _job = null;
      _file = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    return Scaffold(
      key: const Key('data_import_scaffold'),
      appBar: AppBar(title: const Text('Reprise de données')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (job == null) _buildUploadForm(context) else _buildJob(context, job),
            if (_error != null) ...[
              const SizedBox(height: 16),
              NubiaInlineError(
                key: const Key('data_import_error'),
                message: _error!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUploadForm(BuildContext context) {
    return NubiaCard(
      key: const Key('data_import_upload_form'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Importer un fichier CSV',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            "Choisissez le type de données, puis un fichier. Rien n'est "
            "écrit tant que l'import n'est pas lancé.",
          ),
          const SizedBox(height: 12),
          SegmentedControl(
            segments: const ['Patients', 'Rendez-vous'],
            selectedIndex: _kind == DataImportKind.csvPatients ? 0 : 1,
            onChanged: (index) => setState(() {
              _kind = index == 0
                  ? DataImportKind.csvPatients
                  : DataImportKind.csvAppointments;
            }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              NubiaButton(
                key: const Key('data_import_pick_file_button'),
                label: 'Choisir un fichier',
                variant: NubiaButtonVariant.secondary,
                icon: Icons.upload_file_outlined,
                onPressed: _uploading ? null : _pickFile,
              ),
              const SizedBox(width: 12),
              if (_file != null)
                Expanded(
                  child: Text(
                    key: const Key('data_import_selected_file'),
                    _file!.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          NubiaButton(
            key: const Key('data_import_upload_button'),
            label: 'Importer le fichier',
            isLoading: _uploading,
            onPressed: (!_uploading && _file != null) ? _onUpload : null,
          ),
        ],
      ),
    );
  }

  Widget _buildJob(BuildContext context, DataImportJob job) {
    final kindLabel =
        job.kind == DataImportKind.csvPatients ? 'Patients' : 'Rendez-vous';
    return NubiaCard(
      key: const Key('data_import_job_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$kindLabel — ${job.fileName ?? job.sourceSystem}',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _statusPill(job.status),
            ],
          ),
          const SizedBox(height: 16),
          if (job.status == DataImportStatus.failed &&
              job.report.mode == 'upload')
            NubiaInlineError(
              key: const Key('data_import_upload_failed'),
              message: job.report.lines.isNotEmpty
                  ? (job.report.lines.first.message ?? 'Fichier invalide.')
                  : 'Fichier invalide.',
            )
          else ...[
            _buildReportSummary(context, job),
            const SizedBox(height: 12),
            ..._buildReportLines(context, job),
          ],
          const SizedBox(height: 16),
          if (_running) ...[
            const LinearProgressIndicator(key: Key('data_import_progress')),
            const SizedBox(height: 8),
            const Text('Import en cours…'),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _buildActions(context, job),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(DataImportStatus status) {
    return switch (status) {
      DataImportStatus.pending =>
        const StatusPill(label: 'En attente', variant: StatusPillVariant.neutral),
      DataImportStatus.running =>
        const StatusPill(label: 'En cours', variant: StatusPillVariant.progress),
      DataImportStatus.completed =>
        const StatusPill(label: 'Terminé', variant: StatusPillVariant.success),
      DataImportStatus.failed =>
        const StatusPill(label: 'Échec', variant: StatusPillVariant.error),
    };
  }

  Widget _buildReportSummary(BuildContext context, DataImportJob job) {
    final report = job.report;
    final String text = switch (report.mode) {
      'upload' =>
        '${job.totalCount} ligne(s) au total · '
            '${job.totalCount - report.errors} OK · '
            '${report.errors} en erreur',
      'dry_run' =>
        '${report.total} ligne(s) · ${report.created ?? 0} à créer · '
            '${report.updated ?? 0} à mettre à jour · '
            '${report.unchanged ?? 0} inchangée(s) · '
            '${report.errors} en erreur',
      _ =>
        '${job.importedCount} importée(s) · ${job.skippedCount} inchangée(s) · '
            '${job.errorCount} en erreur',
    };
    return Text(
      key: const Key('data_import_report_summary'),
      text,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  List<Widget> _buildReportLines(BuildContext context, DataImportJob job) {
    final okLines =
        job.report.lines.where((l) => l.action != 'error').toList();
    final errorLines =
        job.report.lines.where((l) => l.action == 'error').toList();
    return [
      if (okLines.isNotEmpty)
        NubiaCard(
          key: const Key('data_import_ok_lines'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lignes OK', style: Theme.of(context).textTheme.titleSmall),
              for (final line in okLines)
                Text('Ligne ${line.line} : ${line.action}'),
            ],
          ),
        ),
      if (okLines.isNotEmpty && errorLines.isNotEmpty)
        const SizedBox(height: 12),
      if (errorLines.isNotEmpty)
        NubiaCard(
          key: const Key('data_import_error_lines'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lignes en erreur',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final line in errorLines)
                Text('Ligne ${line.line} : ${line.message ?? 'Erreur'}'),
            ],
          ),
        ),
    ];
  }

  List<Widget> _buildActions(BuildContext context, DataImportJob job) {
    if (job.status == DataImportStatus.failed && job.report.mode == 'upload') {
      return [
        NubiaButton(
          key: const Key('data_import_reset_button'),
          label: 'Recommencer',
          onPressed: _reset,
        ),
      ];
    }
    if (job.report.mode == 'upload') {
      return [
        NubiaButton(
          key: const Key('data_import_dry_run_button'),
          label: "Lancer l'analyse à blanc",
          isLoading: _dryRunning,
          onPressed: _dryRunning ? null : _onDryRun,
        ),
        NubiaButton(
          key: const Key('data_import_reset_button'),
          label: 'Recommencer',
          variant: NubiaButtonVariant.secondary,
          onPressed: (_dryRunning || _running) ? null : _reset,
        ),
      ];
    }
    if (job.report.mode == 'dry_run') {
      return [
        NubiaButton(
          key: const Key('data_import_run_button'),
          label: "Lancer l'import",
          isLoading: _running,
          onPressed: _running ? null : _onRun,
        ),
        NubiaButton(
          key: const Key('data_import_reset_button'),
          label: 'Recommencer',
          variant: NubiaButtonVariant.secondary,
          onPressed: _running ? null : _reset,
        ),
      ];
    }
    // mode == 'run' : import terminé (ou échoué techniquement, cf. AppError
    // interne — `report.errors` couvre déjà les erreurs de lignes).
    return [
      NubiaButton(
        key: const Key('data_import_download_button'),
        label: 'Télécharger le rapport',
        icon: Icons.download_outlined,
        onPressed: _onDownloadReport,
      ),
      NubiaButton(
        key: const Key('data_import_reset_button'),
        label: 'Nouvel import',
        variant: NubiaButtonVariant.secondary,
        onPressed: _reset,
      ),
    ];
  }
}
