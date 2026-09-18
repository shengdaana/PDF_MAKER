import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../services/pdf_service.dart';

class SuccessScreen extends StatefulWidget {
  final PdfGenerationResult result;

  const SuccessScreen({super.key, required this.result});

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  late File _currentFile;
  late String _currentFileName;

  @override
  void initState() {
    super.initState();
    _currentFile = widget.result.file;
    _currentFileName = widget.result.fileName;
  }

  void _sharePdf() {
    Share.shareXFiles(
      [XFile(_currentFile.path)],
      text: 'Sharing PDF: $_currentFileName',
    );
  }

  void _openPdf() async {
    final result = await OpenFilex.open(_currentFile.path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open PDF viewer: ${result.message}')),
      );
    }
  }

  void _showRenameDialog() {
    final strings = AppStateScope.of(context).strings;
    final controller = TextEditingController(
      text: _currentFileName.replaceAll('.pdf', ''),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(strings.get('btn_rename_pdf')),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              suffixText: '.pdf',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(strings.get('cancel_btn')),
            ),
            ElevatedButton(
              onPressed: () async {
                final rawName = controller.text.trim();
                if (rawName.isEmpty) return;

                // 1. Strip characters illegal in filenames
                String sanitized = rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
                if (sanitized.isEmpty) sanitized = "document";

                // 2. Resolve duplicate numbering: file(1).pdf, file(2).pdf
                final parentDir = _currentFile.parent;
                String finalName = "$sanitized.pdf";
                File targetFile = File("${parentDir.path}/$finalName");
                int counter = 1;
                while (await targetFile.exists() && targetFile.path != _currentFile.path) {
                  finalName = "$sanitized($counter).pdf";
                  targetFile = File("${parentDir.path}/$finalName");
                  counter++;
                }

                // 3. Rename file cleanly
                final renamed = await _currentFile.rename(targetFile.path);
                setState(() {
                  _currentFile = renamed;
                  _currentFileName = finalName;
                });

                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Renamed to $finalName')),
                  );
                }
              },
              child: Text(strings.get('btn_confirm')),
            ),
          ],
        );
      },
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final appScope = AppStateScope.of(context);
    final strings = appScope.strings;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.get('app_title')),
        leading: IconButton(
          icon: const Icon(Icons.home_rounded),
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // Header Card: "Your PDF is Created!"
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        strings.get('pdf_ready_title'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        strings.get('pdf_ready_subtitle'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // File Info Card
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.picture_as_pdf_rounded, color: primaryColor, size: 36),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentFileName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${widget.result.pageCount} ${strings.get('pages_selected')} • ${_formatFileSize(widget.result.fileSizeBytes)}',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Text(
                        'Location: ${_currentFile.path}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Action Buttons
              ElevatedButton.icon(
                onPressed: _sharePdf,
                icon: const Icon(Icons.share_rounded, size: 22),
                label: Text(
                  strings.get('btn_share_pdf'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openPdf,
                icon: const Icon(Icons.remove_red_eye_rounded, size: 22),
                label: Text(
                  strings.get('btn_view_pdf'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _showRenameDialog,
                icon: const Icon(Icons.edit_note_rounded, size: 22),
                label: Text(
                  strings.get('btn_rename_pdf'),
                  style: TextStyle(fontSize: 16, color: primaryColor, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
