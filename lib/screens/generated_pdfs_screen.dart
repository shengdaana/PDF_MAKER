import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../models/app_settings.dart';
import '../services/pdf_service.dart';
import 'pdf_detail_screen.dart';

class _PdfFileEntry {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;

  const _PdfFileEntry({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modified,
  });

  File get file => File(path);
}

class GeneratedPdfsScreen extends StatefulWidget {
  const GeneratedPdfsScreen({super.key});

  @override
  State<GeneratedPdfsScreen> createState() => _GeneratedPdfsScreenState();
}

class _GeneratedPdfsScreenState extends State<GeneratedPdfsScreen> {
  List<_PdfFileEntry> _pdfEntries = [];
  List<_PdfFileEntry> _filteredEntries = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Batch selection mode (Export, Share, Delete)
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

  /// Scans directories and reads file metadata (`statSync`) inside a background isolate
  /// so the UI thread never blocks on disk I/O during loading or scrolling.
  Future<void> _loadPdfFiles() async {
    setState(() => _isLoading = true);

    try {
      await _checkStoragePermission();

      final searchDirs = await PdfService.getAllPdfSearchDirectories();
      final List<String> dirPaths = searchDirs.map((d) => d.path).toList();

      final List<_PdfFileEntry> loaded = await Isolate.run(() {
        final Set<String> seenPaths = {};
        final List<_PdfFileEntry> entries = [];

        for (final dirPath in dirPaths) {
          final dir = Directory(dirPath);
          if (!dir.existsSync()) continue;
          try {
            final entities = dir.listSync();
            for (final entity in entities) {
              if (entity is File &&
                  entity.path.toLowerCase().endsWith('.pdf') &&
                  !seenPaths.contains(entity.path)) {
                seenPaths.add(entity.path);
                final stat = entity.statSync();
                final name = entity.uri.pathSegments.last;
                entries.add(
                  _PdfFileEntry(
                    path: entity.path,
                    name: name,
                    sizeBytes: stat.size,
                    modified: stat.modified,
                  ),
                );
              }
            }
          } catch (_) {}
        }

        entries.sort((a, b) => b.modified.compareTo(a.modified));
        return entries;
      });

      _pdfEntries = loaded;
      _applySearch();
    } catch (e) {
      debugPrint('Error loading generated PDF files: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applySearch() {
    if (_searchQuery.trim().isEmpty) {
      _filteredEntries = List.from(_pdfEntries);
    } else {
      final q = _searchQuery.toLowerCase().trim();
      _filteredEntries = _pdfEntries.where((entry) {
        return entry.name.toLowerCase().contains(q);
      }).toList();
    }
  }

  Future<void> _openPdf(_PdfFileEntry entry) async {
    await PdfService.openPdfFile(context, entry.file);
  }

  Future<void> _openPdfDetail(_PdfFileEntry entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfDetailScreen(file: entry.file),
      ),
    );
    if (mounted) {
      _loadPdfFiles();
    }
  }

  void _sharePdf(_PdfFileEntry entry) {
    Share.shareXFiles([XFile(entry.path)], text: entry.name);
  }

  Future<void> _exportSinglePdf(_PdfFileEntry entry) async {
    final strings = AppStateScope.of(context).strings;
    final String? exported = await PdfService.exportPdfToDownloads(entry.file);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          exported != null
              ? '${strings.get('msg_exported_single')} ${entry.name}'
              : strings.get('msg_export_failed'),
        ),
      ),
    );
  }

  void _confirmDeletePdf(_PdfFileEntry entry) {
    final strings = AppStateScope.of(context).strings;
    final fileName = entry.name;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(strings.get('delete_confirm_title')),
        content: Text('${strings.get('delete_confirm_desc')}\n\n"$fileName"'),
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
              try {
                final file = entry.file;
                if (await file.exists()) {
                  await file.delete();
                }
                _loadPdfFiles();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(strings.deletedSingleFile(fileName))),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$e')),
                  );
                }
              }
            },
            child: Text(strings.get('delete_btn')),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(_PdfFileEntry entry) {
    setState(() {
      if (_selectedFilePaths.contains(entry.path)) {
        _selectedFilePaths.remove(entry.path);
        if (_selectedFilePaths.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedFilePaths.add(entry.path);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedFilePaths.length == _filteredEntries.length) {
        _selectedFilePaths.clear();
        _isSelectionMode = false;
      } else {
        _selectedFilePaths.clear();
        for (final entry in _filteredEntries) {
          _selectedFilePaths.add(entry.path);
        }
      }
    });
  }

  void _batchShare() {
    if (_selectedFilePaths.isEmpty) return;
    final List<XFile> xFiles = _selectedFilePaths.map((p) => XFile(p)).toList();
    Share.shareXFiles(
      xFiles,
      text: 'PDF Maker (${_selectedFilePaths.length})',
    );
  }

  Future<void> _batchExportToDownloads() async {
    if (_selectedFilePaths.isEmpty || _isExporting) return;
    final strings = AppStateScope.of(context).strings;

    setState(() => _isExporting = true);
    try {
      final int exportedCount =
          await PdfService.batchExportPdfsToDownloads(_selectedFilePaths);
      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _selectedFilePaths.clear();
        _isSelectionMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            exportedCount > 0
                ? strings.exportedMultipleFiles(exportedCount)
                : strings.get('msg_export_failed'),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _batchDelete() {
    if (_selectedFilePaths.isEmpty) return;
    final strings = AppStateScope.of(context).strings;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(strings.deleteMultipleTitle(_selectedFilePaths.length)),
        content: Text(strings.get('delete_batch_desc')),
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
              int count = 0;
              for (final path in _selectedFilePaths) {
                try {
                  final f = File(path);
                  if (await f.exists()) {
                    await f.delete();
                    count++;
                  }
                } catch (_) {}
              }
              setState(() {
                _selectedFilePaths.clear();
                _isSelectionMode = false;
              });
              _loadPdfFiles();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(strings.deletedMultipleFiles(count))),
                );
              }
            },
            child: Text(strings.get('delete_all_btn')),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Map<String, List<_PdfFileEntry>> _groupByDate(List<_PdfFileEntry> entries, AppStrings strings) {
    final Map<String, List<_PdfFileEntry>> groups = {};
    for (final entry in entries) {
      final header = strings.formatDateHeader(entry.modified);
      groups.putIfAbsent(header, () => []).add(entry);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final appScope = AppStateScope.of(context);
    final strings = appScope.strings;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final groupedEntries = _groupByDate(_filteredEntries, strings);

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
          if (!_isSelectionMode && _filteredEntries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: strings.get('tooltip_batch_select'),
              onPressed: () => setState(() => _isSelectionMode = true),
            ),
          if (_isSelectionMode)
            IconButton(
              icon: Icon(
                _selectedFilePaths.length == _filteredEntries.length
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              ),
              tooltip: strings.get('select_all'),
              onPressed: _toggleSelectAll,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: strings.get('tooltip_refresh'),
            onPressed: _loadPdfFiles,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            if (_pdfEntries.isNotEmpty && !_isSelectionMode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: strings.get('search_pdfs_hint'),
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

            // Main PDF List (Zero disk I/O during build/scroll)
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredEntries.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.folder_open_rounded,
                                  size: 64,
                                  color: primaryColor.withOpacity(0.4),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? '${strings.get('no_pdfs_match')} "$_searchQuery"'
                                      : strings.get('no_pdfs_yet'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadPdfFiles,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                            itemCount: groupedEntries.keys.length,
                            itemBuilder: (context, groupIndex) {
                              final header = groupedEntries.keys.elementAt(groupIndex);
                              final entriesInGroup = groupedEntries[header]!;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Date Group Header
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                                    child: Row(
                                      children: [
                                        Icon(Icons.calendar_today_rounded, size: 14, color: primaryColor),
                                        const SizedBox(width: 6),
                                        Text(
                                          header,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: primaryColor,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '(${entriesInGroup.length})',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // PDF Rows in this date group
                                  ...entriesInGroup.map((entry) {
                                    final bool isSelected = _selectedFilePaths.contains(entry.path);

                                    return RepaintBoundary(
                                      child: Card(
                                        key: ValueKey(entry.path),
                                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                                        elevation: 1,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          side: isSelected
                                              ? BorderSide(color: primaryColor, width: 2)
                                              : BorderSide(
                                                  color: theme.colorScheme.outline.withOpacity(0.12),
                                                ),
                                        ),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(14),
                                          onTap: () {
                                            if (_isSelectionMode) {
                                              _toggleSelection(entry);
                                            } else {
                                              _openPdf(entry);
                                            }
                                          },
                                          onLongPress: () {
                                            if (!_isSelectionMode) {
                                              setState(() {
                                                _isSelectionMode = true;
                                                _selectedFilePaths.add(entry.path);
                                              });
                                            }
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12.0,
                                              vertical: 10.0,
                                            ),
                                            child: Row(
                                              children: [
                                                if (_isSelectionMode)
                                                  Padding(
                                                    padding: const EdgeInsets.only(right: 8.0),
                                                    child: Checkbox(
                                                      value: isSelected,
                                                      onChanged: (_) => _toggleSelection(entry),
                                                    ),
                                                  )
                                                else
                                                  Container(
                                                    padding: const EdgeInsets.all(10),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.shade50,
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(color: Colors.red.shade100),
                                                    ),
                                                    child: const Icon(
                                                      Icons.picture_as_pdf_rounded,
                                                      color: Colors.red,
                                                      size: 26,
                                                    ),
                                                  ),
                                                const SizedBox(width: 12),

                                                // File Info: Pre-computed Filename, Time & Size
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        entry.name,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        '${_formatTime(entry.modified)} • ${_formatFileSize(entry.sizeBytes)}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: theme.colorScheme.onSurface
                                                              .withOpacity(0.6),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // Quick Actions: Preview/Edit, Export to Downloads, Share, Delete
                                                if (!_isSelectionMode) ...[
                                                  IconButton(
                                                    icon: const Icon(Icons.edit_document, size: 20),
                                                    tooltip: strings.get('tooltip_edit_pdf'),
                                                    onPressed: () => _openPdfDetail(entry),
                                                    visualDensity: VisualDensity.compact,
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.download_rounded, size: 20),
                                                    tooltip: strings.get('tooltip_export_pdf'),
                                                    onPressed: () => _exportSinglePdf(entry),
                                                    visualDensity: VisualDensity.compact,
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.share_outlined, size: 20),
                                                    tooltip: strings.get('btn_share_pdf'),
                                                    onPressed: () => _sharePdf(entry),
                                                    visualDensity: VisualDensity.compact,
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete_outline_rounded,
                                                      size: 20,
                                                      color: Colors.redAccent,
                                                    ),
                                                    tooltip: strings.get('delete_btn'),
                                                    onPressed: () => _confirmDeletePdf(entry),
                                                    visualDensity: VisualDensity.compact,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              );
                            },
                          ),
                        ),
            ),

            // Batch Action Bottom Bar (Batch Delete, Batch Export to Downloads, Batch Share)
            if (_isSelectionMode && _selectedFilePaths.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 6,
                      offset: Offset(0, -2),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    // 1. Batch Delete
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _isExporting ? null : _batchDelete,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${strings.get('delete_btn')} (${_selectedFilePaths.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 2. Batch Export to Downloads
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _isExporting ? null : _batchExportToDownloads,
                        icon: _isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_rounded, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${strings.get('batch_export_short')} (${_selectedFilePaths.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 3. Batch Share
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _isExporting ? null : _batchShare,
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${strings.get('btn_share_short')} (${_selectedFilePaths.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
