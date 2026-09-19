import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import 'pdf_editor_screen.dart';

class PdfDetailScreen extends StatefulWidget {
  final File file;

  const PdfDetailScreen({super.key, required this.file});

  @override
  State<PdfDetailScreen> createState() => _PdfDetailScreenState();
}

class _PdfDetailScreenState extends State<PdfDetailScreen> {
  late File _currentFile;
  late String _currentFileName;
  List<Uint8List> _pagePreviews = [];
  bool _isLoadingPreviews = true;

  @override
  void initState() {
    super.initState();
    _currentFile = widget.file;
    _currentFileName = widget.file.uri.pathSegments.last;
    _loadPagePreviews();
  }

  Future<void> _loadPagePreviews() async {
    setState(() => _isLoadingPreviews = true);
    final List<Uint8List> loaded = [];

    try {
      if (await _currentFile.exists()) {
        final Uint8List pdfBytes = await _currentFile.readAsBytes();
        // Rasterize first 15 pages for snappy performance
        int count = 0;
        await for (final page in Printing.raster(pdfBytes, dpi: 100)) {
          final pngBytes = await page.toPng();
          loaded.add(pngBytes);
          count++;
          if (count >= 20) break;
        }
      }
    } catch (e) {
      debugPrint("Error loading PDF page previews: $e");
    } finally {
      if (mounted) {
        setState(() {
          _pagePreviews = loaded;
          _isLoadingPreviews = false;
        });
      }
    }
  }

  void _sharePdf() {
    Share.shareXFiles(
      [XFile(_currentFile.path)],
      text: 'PDF: $_currentFileName',
    );
  }

  void _openInExternalViewer() async {
    final result = await OpenFilex.open(_currentFile.path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open PDF viewer: ${result.message}')),
      );
    }
  }

  void _deletePdf() {
    final strings = AppStateScope.of(context).strings;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(strings.get('delete_confirm_title')),
          content: Text(strings.get('delete_confirm_desc')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(strings.get('cancel_btn')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                try {
                  await _currentFile.delete();
                  if (mounted) {
                    Navigator.pop(ctx); // close dialog
                    Navigator.pop(context, true); // pop back to list with deleted flag
                  }
                } catch (e) {
                  debugPrint("Error deleting PDF: $e");
                }
              },
              child: Text(strings.get('delete_btn')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openPdfEditor() async {
    final updatedFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => PdfEditorScreen(pdfFile: _currentFile),
      ),
    );

    if (updatedFile != null && mounted) {
      setState(() {
        _currentFile = updatedFile;
        _currentFileName = updatedFile.uri.pathSegments.last;
      });
      _loadPagePreviews();
    }
  }

  void _showRenameDialog() {
    final strings = AppStateScope.of(context).strings;
    final nameWithoutExt = _currentFileName.endsWith('.pdf')
        ? _currentFileName.substring(0, _currentFileName.length - 4)
        : _currentFileName;

    final controller = TextEditingController(text: nameWithoutExt);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, size: 28),
              const SizedBox(width: 10),
              Text(strings.get('btn_rename_pdf')),
            ],
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Document Name',
              suffixText: '.pdf',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(strings.get('cancel_btn')),
            ),
            ElevatedButton(
              onPressed: () async {
                final raw = controller.text.trim();
                if (raw.isEmpty) return;

                String sanitized = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
                if (sanitized.isEmpty) sanitized = "document";

                final parentDir = _currentFile.parent;
                String finalName = "$sanitized.pdf";
                File targetFile = File("${parentDir.path}/$finalName");

                int counter = 1;
                while (await targetFile.exists() && targetFile.path != _currentFile.path) {
                  finalName = "$sanitized($counter).pdf";
                  targetFile = File("${parentDir.path}/$finalName");
                  counter++;
                }

                if (targetFile.path == _currentFile.path) {
                  Navigator.pop(ctx);
                  return;
                }

                try {
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
                } catch (e) {
                  debugPrint("Error renaming: $e");
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

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final appScope = AppStateScope.of(context);
    final strings = appScope.strings;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final stat = _currentFile.existsSync() ? _currentFile.statSync() : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentFileName,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded),
            tooltip: 'Open in system viewer',
            onPressed: _openInExternalViewer,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: 'Rename',
            onPressed: _showRenameDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Document Info Header Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.picture_as_pdf_rounded,
                          color: primaryColor,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentFileName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 4),
                            if (stat != null)
                              Text(
                                '${_formatFileSize(stat.size)} • ${_formatDate(stat.modified)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Page Previews Grid / Flip View
            Expanded(
              child: _isLoadingPreviews
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Rendering page previews...'),
                        ],
                      ),
                    )
                  : _pagePreviews.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.description_outlined,
                                  size: 64, color: primaryColor.withOpacity(0.4)),
                              const SizedBox(height: 12),
                              const Text('Tap "View in System Viewer" to open this document'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          scrollDirection: Axis.horizontal,
                          itemCount: _pagePreviews.length,
                          itemBuilder: (context, index) {
                            return Container(
                              width: 260,
                              margin: const EdgeInsets.only(right: 14.0),
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: theme.colorScheme.outline.withOpacity(0.15),
                                  ),
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.memory(
                                      _pagePreviews[index],
                                      fit: BoxFit.contain,
                                    ),
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.7),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Page ${index + 1} of ${_pagePreviews.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Three Main Action Buttons: Share, Delete, and Edit PDF
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: theme.cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  )
                ],
              ),
              child: Row(
                children: [
                  // 1. Share Button
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: _sharePdf,
                      icon: const Icon(Icons.share_rounded, size: 20),
                      label: FittedBox(
                        child: Text(
                          strings.get('btn_share_pdf'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. Delete Button
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent, width: 1.5),
                        minimumSize: const Size(0, 50),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: _deletePdf,
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      label: FittedBox(
                        child: Text(
                          strings.get('delete_btn'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. Edit PDF Button (Prominent Primary Button)
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: _openPdfEditor,
                      icon: const Icon(Icons.edit_document, size: 20),
                      label: FittedBox(
                        child: Text(
                          strings.get('edit_pdf'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
