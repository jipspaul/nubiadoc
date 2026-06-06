import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_bloc.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_event.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_state.dart';
import 'package:nubia_patient/presentation/features/documents/widgets/document_category_selector.dart';
import 'package:nubia_patient/presentation/features/documents/widgets/document_file_picker_button.dart';

/// Upload screen — allows the patient to send a document to the vault.
///
/// Provides its own [DocumentBloc] (isolated from the list bloc) and listens
/// for [DocumentUploadSuccess] to pop back automatically.
class DocumentUploadScreen extends StatelessWidget {
  const DocumentUploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<DocumentBloc>(),
      child: const _DocumentUploadBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _DocumentUploadBody extends StatefulWidget {
  const _DocumentUploadBody();

  @override
  State<_DocumentUploadBody> createState() => _DocumentUploadBodyState();
}

class _DocumentUploadBodyState extends State<_DocumentUploadBody> {
  DocumentCategory _selectedCategory = DocumentCategory.other;
  String? _filePath;
  String? _filename;
  String? _mimeType;

  void _onFileSelected({
    required String path,
    required String name,
    required String mime,
  }) {
    setState(() {
      _filePath = path;
      _filename = name;
      _mimeType = mime;
    });
  }

  void _submit() {
    final path = _filePath;
    final name = _filename;
    final mime = _mimeType;
    if (path == null || name == null || mime == null) return;
    context.read<DocumentBloc>().add(
          DocumentUploadRequested(
            filePath: path,
            filename: name,
            mimeType: mime,
            category: _selectedCategory,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DocumentBloc, DocumentState>(
      listener: (context, state) {
        if (state is DocumentUploadSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document envoyé avec succès.')),
          );
          context.pop();
        }
        if (state is DocumentUploadFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Envoyer un document')),
        body: BlocBuilder<DocumentBloc, DocumentState>(
          builder: (context, state) {
            final isUploading = state is DocumentUploading;
            return _UploadForm(
              selectedCategory: _selectedCategory,
              filename: _filename,
              isUploading: isUploading,
              onCategoryChanged: (cat) =>
                  setState(() => _selectedCategory = cat),
              onFileSelected: _onFileSelected,
              onSubmit: _filePath != null && !isUploading ? _submit : null,
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _UploadForm extends StatelessWidget {
  const _UploadForm({
    required this.selectedCategory,
    required this.filename,
    required this.isUploading,
    required this.onCategoryChanged,
    required this.onFileSelected,
    required this.onSubmit,
  });

  final DocumentCategory selectedCategory;
  final String? filename;
  final bool isUploading;
  final ValueChanged<DocumentCategory> onCategoryChanged;
  final void Function({
    required String path,
    required String name,
    required String mime,
  }) onFileSelected;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DocumentCategorySelector(
          selected: selectedCategory,
          onChanged: onCategoryChanged,
        ),
        const SizedBox(height: 24),
        DocumentFilePickerButton(
          filename: filename,
          onFileSelected: onFileSelected,
        ),
        const SizedBox(height: 32),
        FilledButton(
          key: const Key('upload_submit'),
          onPressed: onSubmit,
          child: isUploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Envoyer'),
        ),
      ],
    );
  }
}
