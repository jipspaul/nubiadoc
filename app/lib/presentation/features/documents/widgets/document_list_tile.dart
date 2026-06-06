import 'package:flutter/material.dart';
import 'package:nubia_patient/core/utils/document_opener.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// A list tile representing a single [Document].
///
/// Displays the document name, MIME type label, and creation date.
/// [onTap] navigates to the detail screen; [onDownload] triggers signed-URL
/// fetch + open.
class DocumentListTile extends StatelessWidget {
  const DocumentListTile({
    super.key,
    required this.document,
    required this.onTap,
    required this.onDownload,
  });

  final Document document;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      leading: Icon(
        _iconFor(document.mimeType),
        color: colorScheme.primary,
      ),
      title: Text(document.name, style: textTheme.bodyMedium),
      subtitle: Text(
        '${mimeTypeLabel(document.mimeType)} · ${_formatDate(document.createdAt)}',
        style: textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.download_outlined),
        color: colorScheme.primary,
        tooltip: 'Télécharger',
        onPressed: onDownload,
      ),
      onTap: onTap,
    );
  }

  static IconData _iconFor(String mimeType) {
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  static String _formatDate(DateTime date) {
    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}
