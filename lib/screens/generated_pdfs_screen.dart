import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../services/pdf_service.dart';
import 'pdf_detail_screen.dart';

class GeneratedPdfsScreen extends StatefulWidget {
  const GeneratedPdfsScreen({super.key});

  @override
  State<GeneratedPdfsScreen> createState() => _GeneratedPdfsScreenState();
}

class _GeneratedPdfsScreenState extends State<GeneratedPdfsScreen> {
  List<File> _pdfFiles = [];
  List<File> _filteredFiles = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Batch Selection State
  bool _isSelectionMode = false;
  final Set<String> _selectedFilePaths = {};

  @override
  void initState() {
    super.initState();
    _loadPdfFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;
      if (!status.isGranted) {
        await Permission.storage.request();
      }
    }
  }

  Future<void> _loadPdfFiles() async {
    setState(() => _isLoading = true);

    try {
      await _checkStoragePermission();

      final searchDirs = await PdfService.getAllPdfSearchDirectories();
      final Set<String> seenPaths = {};
      final List<File> loaded = [];

      for (final dir in searchDirs) {
        if (await dir.exists()) {
          final entities = dir.listSync();
          for (final entity in entities) {
            if (entity is File &&
                entity.path.toLowerCase().endsWith('.pdf') &&
                !seenPaths.contains(entity.path)) {
              seenPaths.add(entity.path);
              loaded.add(entity);
            }
          }
        }
      }

      // Sort newest first
      loaded.sort((a, b) {
        final aTime = a.statSync().modified;
        final bTime = b.statSync().modified;
        return bTime.compareTo(aTime);
      });

      _pdfFiles = loaded;
      _applySearch();
    } catch (e) {
      debugPrint("Error loading generated PDF files: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applySearch() {
    if (_searchQuery.trim().isEmpty) {
      _filteredFiles = List.from(_pdfFiles);
    } else {
      final q = _searchQuery.toLowerCase().trim();
      _filteredFiles = _pdfFiles.where((f) {
        final name = f.uri.pathSegments.last.toLowerCase();
        return name.contains(q);
      }).toList();
    }
  }

  void _openDetailScreen(File file) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PdfDetailScreen(file: file),
      ),
    );

    if (result == true || mounted) {
      _loadPdfFiles();
    }
  }

  void _toggleSelection(File file) {
    setState(() {
      if (_selectedFilePaths.contains(file.path)) {
        _selectedFilePaths.remove(file.path);
        if (_selectedFilePaths.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedFilePaths.add(file.path);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedFilePaths.length == _filteredFiles.length) {
        _selectedFilePaths.clear();
        _isSelectionMode = false;
      } else {
        _selectedFilePaths.clear();
        for (final file in _filteredFiles) {
          _selectedFilePaths.add(file.path);
        }
      }
    });
  }

  void _batchExport() {
    if (_selectedFilePaths.isEmpty) return;
    final List<XFile> xFiles = _selectedFilePaths.map((p) => XFile(p)).toList();
    Share.shareXFiles(
      xFiles,
      text: 'Sharing ${_selectedFilePaths.length} PDF documents from PDF Maker Pro',
    );
  }

  void _batchDelete() {
    if (_selectedFilePaths.isEmpty) return;
    final strings = AppStateScope.of(context).strings;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('${strings.get('batch_delete')} (${_selectedFilePaths.length})'),
          content: Text(
            'Are you sure you want to permanently delete ${_selectedFilePaths.length} selected PDF files?',
          ),
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
                Navigator.pop(ctx);
                for (final path in _selectedFilePaths) {
                  try {
                    final f = File(path);
                    if (await f.exists()) {
                      await f.delete();
                    }
                  } catch (e) {
                    debugPrint("Error deleting $path: $e");
                  }
                }
                setState(() {
                  _selectedFilePaths.clear();
                  _isSelectionMode = false;
                });
                _loadPdfFiles();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Selected PDFs deleted.')),
                  );
                }
              },
              child: Text(strings.get('delete_btn')),
            ),
          ],
        );
      },
    );
  }

  void _showRenameDialog(File file) {
    final strings = AppStateScope.of(context).strings;
    final currentName = file.uri.pathSegments.last;
    final nameWithoutExt = currentName.endsWith('.pdf')
        ? currentName.substring(0, currentName.length - 4)
        : currentName;

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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Document Name',
                  suffixText: '.pdf',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Special characters (\\ / : * ? " < > |) will be sanitized.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                    ),
              ),
            ],
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

                String sanitized = rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
                if (sanitized.isEmpty) sanitized = "document";

                final parentDir = file.parent;
                String finalName = "$sanitized.pdf";
                File targetFile = File("${parentDir.path}/$finalName");

                int counter = 1;
                while (await targetFile.exists() && targetFile.path != file.path) {
                  finalName = "$sanitized($counter).pdf";
                  targetFile = File("${parentDir.path}/$finalName");
                  counter++;
                }

                if (targetFile.path == file.path) {
                  Navigator.pop(ctx);
                  return;
                }

                try {
                  await file.rename(targetFile.path);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Renamed to $finalName')),
                    );
                    _loadPdfFiles();
                  }
                } catch (e) {
                  debugPrint("Rename failed: $e");
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Rename failed: $e')),
                    );
                  }
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
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final appScope = AppStateScope.of(context);
    final strings = appScope.strings;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final bool enableAnim = appScope.settings.premiumAnimations;

    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedFilePaths.clear();
                  });
                },
              )
            : null,
        title: Text(
          _isSelectionMode
              ? '${_selectedFilePaths.length} ${strings.get('selected_count')}'
              : strings.get('btn_see_pdfs'),
        ),
        actions: [
          if (!_isSelectionMode && _filteredFiles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: 'Batch Selection',
              onPressed: () {
                setState(() => _isSelectionMode = true);
              },
            ),
          if (_isSelectionMode)
            IconButton(
              icon: Icon(
                _selectedFilePaths.length == _filteredFiles.length
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              ),
              tooltip: strings.get('select_all'),
              onPressed: _toggleSelectAll,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh list',
            onPressed: _loadPdfFiles,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            if (_pdfFiles.isNotEmpty && !_isSelectionMode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search generated PDFs...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _applySearch();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3)),
                    ),
                    filled: true,
                    fillColor: theme.cardColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                      _applySearch();
                    });
                  },
                ),
              ),

            // Main Content Area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredFiles.isEmpty
                      ? RefreshIndicator(
                          onRefresh: _loadPdfFiles,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.folder_open_rounded,
                                        size: 72,
                                        color: primaryColor.withOpacity(0.35),
                                      ),
                                      const SizedBox(height: 18),
                                      Text(
                                        _searchQuery.isNotEmpty
                                            ? 'No PDFs match "$_searchQuery"'
                                            : strings.get('no_pdfs_yet'),
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          color: theme.colorScheme.onSurface.withOpacity(0.65),
                                          height: 1.4,
                                        ),
                                      ),
                                      if (_searchQuery.isEmpty) ...[
                                        const SizedBox(height: 24),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size(200, 48),
                                          ),
                                          onPressed: () => Navigator.of(context).pop(),
                                          icon: const Icon(Icons.add_photo_alternate_rounded),
                                          label: Text(strings.get('btn_select_gallery')),
                                        ),
                                      ]
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadPdfFiles,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            itemCount: _filteredFiles.length,
                            itemBuilder: (context, index) {
                              final file = _filteredFiles[index];
                              final name = file.uri.pathSegments.last;
                              final stat = file.existsSync() ? file.statSync() : null;
                              final isSelected = _selectedFilePaths.contains(file.path);

                              Widget cardWidget = Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: isSelected
                                      ? BorderSide(color: primaryColor, width: 2)
                                      : BorderSide.none,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    if (_isSelectionMode) {
                                      _toggleSelection(file);
                                    } else {
                                      _openDetailScreen(file);
                                    }
                                  },
                                  onLongPress: () {
                                    if (!_isSelectionMode) {
                                      setState(() {
                                        _isSelectionMode = true;
                                        _selectedFilePaths.add(file.path);
                                      });
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(14.0),
                                    child: Row(
                                      children: [
                                        // Checkbox in selection mode or PDF Icon Badge
                                        if (_isSelectionMode)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 8.0),
                                            child: Checkbox(
                                              value: isSelected,
                                              onChanged: (_) => _toggleSelection(file),
                                            ),
                                          )
                                        else
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

                                        // File Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
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
                                                    color:
                                                        theme.colorScheme.onSurface.withOpacity(0.6),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),

                                        // Action icon / Arrow in normal mode
                                        if (!_isSelectionMode)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit_note_rounded, size: 22),
                                                tooltip: 'Rename',
                                                onPressed: () => _showRenameDialog(file),
                                              ),
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                                color: Colors.grey,
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );

                              if (enableAnim) {
                                return AnimatedOpacity(
                                  duration: const Duration(milliseconds: 250),
                                  opacity: 1.0,
                                  child: cardWidget,
                                );
                              }
                              return cardWidget;
                            },
                          ),
                        ),
            ),

            // Batch Actions Floating Bottom Bar
            if (_isSelectionMode && _selectedFilePaths.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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
                    // Batch Delete Button
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent, width: 1.5),
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _batchDelete,
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        label: FittedBox(
                          child: Text(
                            '${strings.get('batch_delete')} (${_selectedFilePaths.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Batch Export / Share Button
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _batchExport,
                        icon: const Icon(Icons.share_rounded, size: 20),
                        label: FittedBox(
                          child: Text(
                            '${strings.get('batch_export')} (${_selectedFilePaths.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
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
