import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../models/app_settings.dart';
import '../services/pdf_service.dart';

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

  // Batch selection mode
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

      // Sort newest modified first
      loaded.sort((a, b) {
        final aTime = a.statSync().modified;
        final bTime = b.statSync().modified;
        return bTime.compareTo(aTime);
      });

      _pdfFiles = loaded;
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
      _filteredFiles = List.from(_pdfFiles);
    } else {
      final q = _searchQuery.toLowerCase().trim();
      _filteredFiles = _pdfFiles.where((f) {
        final name = f.uri.pathSegments.last.toLowerCase();
        return name.contains(q);
      }).toList();
    }
  }

  Future<void> _openPdf(File file) async {
    await PdfService.openPdfFile(context, file);
  }

  void _sharePdf(File file) {
    Share.shareXFiles([XFile(file.path)], text: file.uri.pathSegments.last);
  }

  void _confirmDeletePdf(File file) {
    final strings = AppStateScope.of(context).strings;
    final fileName = file.uri.pathSegments.last;

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

  void _batchShare() {
    if (_selectedFilePaths.isEmpty) return;
    final List<XFile> xFiles = _selectedFilePaths.map((p) => XFile(p)).toList();
    Share.shareXFiles(
      xFiles,
      text: 'PDF Maker (${_selectedFilePaths.length})',
    );
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

  Map<String, List<File>> _groupByDate(List<File> files, AppStrings strings) {
    final Map<String, List<File>> groups = {};
    for (final file in files) {
      final modified = file.statSync().modified;
      final header = strings.formatDateHeader(modified);
      groups.putIfAbsent(header, () => []).add(file);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final appScope = AppStateScope.of(context);
    final strings = appScope.strings;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final groupedFiles = _groupByDate(_filteredFiles, strings);

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
              tooltip: strings.get('tooltip_batch_select'),
              onPressed: () => setState(() => _isSelectionMode = true),
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
            tooltip: strings.get('tooltip_refresh'),
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

            // Main PDF List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredFiles.isEmpty
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
                            itemCount: groupedFiles.keys.length,
                            itemBuilder: (context, groupIndex) {
                              final header = groupedFiles.keys.elementAt(groupIndex);
                              final filesInGroup = groupedFiles[header]!;

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
                                          '(${filesInGroup.length})',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // PDF Rows in this date group
                                  ...filesInGroup.map((file) {
                                    final name = file.uri.pathSegments.last;
                                    final stat = file.statSync();
                                    final bool isSelected = _selectedFilePaths.contains(file.path);

                                    return Card(
                                      key: ValueKey(file.path),
                                      margin: const EdgeInsets.symmetric(vertical: 4.0),
                                      elevation: 1,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        side: isSelected
                                            ? BorderSide(color: primaryColor, width: 2)
                                            : BorderSide(color: theme.colorScheme.outline.withOpacity(0.12)),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () {
                                          if (_isSelectionMode) {
                                            _toggleSelection(file);
                                          } else {
                                            // Tapping opens/previews the PDF via FileProvider (FIX 3)
                                            _openPdf(file);
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
                                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                                          child: Row(
                                            children: [
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

                                              // File Info: Filename & Date stamp
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      name,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      '${_formatTime(stat.modified)} • ${_formatFileSize(stat.size)}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),

                                              // TWO ACTION BUTTONS: Share and Delete
                                              if (!_isSelectionMode) ...[
                                                IconButton(
                                                  icon: const Icon(Icons.share_outlined, size: 20),
                                                  tooltip: strings.get('btn_share_pdf'),
                                                  onPressed: () => _sharePdf(file),
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                                                  tooltip: strings.get('delete_btn'),
                                                  onPressed: () => _confirmDeletePdf(file),
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                              ],
                                            ],
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

            // Batch Action Bottom Bar
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
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: _batchDelete,
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        label: Text('${strings.get('delete_btn')} (${_selectedFilePaths.length})'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: _batchShare,
                        icon: const Icon(Icons.share_rounded, size: 20),
                        label: Text('${strings.get('btn_share_short')} (${_selectedFilePaths.length})'),
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
