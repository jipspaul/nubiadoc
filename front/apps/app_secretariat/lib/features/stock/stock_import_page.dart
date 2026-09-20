import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Écran d'import CSV d'une facture fournisseur (#7182/#7183, format
/// `ref;libellé;quantité;prix`, `prix` optionnel) — crédite la localisation
/// principale du cabinet et affiche un rapport (lignes importées + lignes
/// rejetées). `POST /v1/stock/import`.
class StockImportPage extends StatefulWidget {
  const StockImportPage({super.key});

  @override
  State<StockImportPage> createState() => _StockImportPageState();
}

class _StockImportPageState extends State<StockImportPage> {
  final _csvController = TextEditingController();
  bool _submitting = false;
  String? _error;
  StockImportResult? _result;

  @override
  void dispose() {
    _csvController.dispose();
    super.dispose();
  }

  Future<void> _onImport() async {
    final csv = _csvController.text.trim();
    if (csv.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collez le contenu CSV à importer.')),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _result = null;
    });
    final result = await GetIt.instance<ImportStockCsvUseCase>()(csv);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _submitting = false;
        _error = failure.message;
      }),
      (report) => setState(() {
        _submitting = false;
        _result = report;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import CSV stock')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Format : ref;libellé;quantité;prix (prix optionnel).'),
          const SizedBox(height: 12),
          NubiaTextField(
            key: const Key('stock_import_csv_field'),
            variant: NubiaTextFieldVariant.multiline,
            controller: _csvController,
            label: 'Contenu CSV',
            maxLines: 10,
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('stock_import_submit_button'),
            onPressed: _submitting ? null : _onImport,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Importer'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            NubiaErrorWidget(message: _error!, onRetry: _onImport),
          ],
          if (_result != null) ..._buildReport(_result!),
        ],
      ),
    );
  }

  List<Widget> _buildReport(StockImportResult result) {
    return [
      const SizedBox(height: 24),
      Text(
        key: const Key('stock_import_report_summary'),
        '${result.imported.length} ligne(s) importée(s) · '
        '${result.errors.length} erreur(s)',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      if (result.imported.isNotEmpty)
        NubiaCard(
          key: const Key('stock_import_imported_list'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Importées', style: Theme.of(context).textTheme.titleSmall),
              for (final line in result.imported)
                Text('Ligne ${line.line} : ${line.reference} × ${line.quantity}'),
            ],
          ),
        ),
      if (result.errors.isNotEmpty) ...[
        const SizedBox(height: 12),
        NubiaCard(
          key: const Key('stock_import_errors_list'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rejetées', style: Theme.of(context).textTheme.titleSmall),
              for (final error in result.errors)
                Text('Ligne ${error.line} : ${error.error} (${error.raw})'),
            ],
          ),
        ),
      ],
    ];
  }
}
