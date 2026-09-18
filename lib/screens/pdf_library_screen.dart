import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';

class PdfLibraryScreen extends StatefulWidget {
  const PdfLibraryScreen({super.key});

  @override
  State<PdfLibraryScreen> createState() => _PdfLibraryScreenState();
}

class _PdfLibraryScreenState extends State<PdfLibraryScreen> {
  List<FileSystemEntity> _pdfFiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPdfFiles();
  }

  Future<void> _loadPdfFiles() async {
    setState(() => _isLoading = true);

    try {
      Directory baseDir;
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          baseDir = Directory("${extDir.path}/PDF documents(pdf_maker)");
        } else {
          final docDir = await getApplicationDocumentsDirectory();
          baseDir = Directory("${docDir.path}/PDF documents(pdf_maker)");
        }
      } catch (_) {
        final docDir = await getApplicationDocumentsDirectory();
        baseDir = Directory("${docDir.path}/PDF documents(pdf_maker)");
      }

      if (await baseDir.exists()) {
        final files = baseDir
            .listSync()
            .where((f) => f.path.toLowerCase().endsWith('.pdf'))
            .toList();
        // Sort newest first
        files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        _pdfFiles = files;
      } else {
        _pdfFiles = [];
      }
    } catch (e) {
      debugPrint("Error loading PDF files: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openFile(File file) async {
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open file: ${result.message}')),
      );
    }
  }

  void _shareFile(File file) {
    Share.shareXFiles([XFile(file.path)], text: 'Sharing PDF');
  }

  void _deleteFile(File file) {
    final strings = AppStateScope.of(context).strings;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(strings.get('delete_confirm_title')),
          content: Text(strings.get('delete_confirm_desc')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(strings.get('cancel_btn')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                try {
                  await file.delete();
                  Navigator.pop(ctx);
                  _loadPdfFiles();
                } catch (e) {
                  debugPrint("Error deleting file: $e");
                }
              },
              child: Text(strings.get('delete_btn')),
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
        title: Text(strings.get('btn_see_pdfs')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadPdfFiles,
          )
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _pdfFiles.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open_rounded, size: 64, color: primaryColor.withOpacity(0.4)),
                          const SizedBox(height: 16),
                          Text(
                            strings.get('no_pdfs_yet'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _pdfFiles.length,
                    itemBuilder: (context, index) {
                      final file = File(_pdfFiles[index].path);
                      final name = file.uri.pathSegments.last;
                      final stat = file.statSync();

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.picture_as_pdf_rounded, color: primaryColor, size: 28),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              '${_formatFileSize(stat.size)} • ${stat.modified.day}/${stat.modified.month}/${stat.modified.year}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.share_rounded, size: 20),
                                onPressed: () => _shareFile(file),
                                tooltip: 'Share',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                                onPressed: () => _deleteFile(file),
                                tooltip: 'Delete',
                              ),
                            ],
                          ),
                          onTap: () => _openFile(file),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
