import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../main.dart';
import '../models/app_settings.dart';
import '../models/pdf_page_item.dart';
import '../utils/image_processor.dart';

class PdfGenerationResult {
  final File file;
  final String fileName;
  final int pageCount;
  final int fileSizeBytes;
  final String savedPath;

  PdfGenerationResult({
    required this.file,
    required this.fileName,
    required this.pageCount,
    required this.fileSizeBytes,
    required this.savedPath,
  });
}

class _OcrLineBox {
  final String text;
  final double left;
  final double top;
  final double width;
  final double height;

  const _OcrLineBox({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

class _PreparedPdfPage {
  final Uint8List compressedBytes;
  final double width;
  final double height;
  final List<_OcrLineBox> ocrLines;

  const _PreparedPdfPage({
    required this.compressedBytes,
    required this.width,
    required this.height,
    required this.ocrLines,
  });
}

class _PageRenderJob {
  final int jobIndex;
  final int displayPageNumber;
  final PdfPageItem primary;
  final PdfPageItem? mergedNext;

  const _PageRenderJob({
    required this.jobIndex,
    required this.displayPageNumber,
    required this.primary,
    this.mergedNext,
  });
}

class PdfService {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.introbird.pdfmakerflutter/native_files');

  /// Opens a generated PDF file using Android's FileProvider or content:// URI and
  /// standard ACTION_VIEW intent — works with both local and SAF paths.
  static Future<void> openPdfFile(BuildContext context, dynamic fileOrPath) async {
    final strings = AppStateScope.of(context).strings;
    final String path = fileOrPath is File ? fileOrPath.path : fileOrPath.toString();
    try {
      await _nativeChannel.invokeMethod('openPdf', {'path': path});
    } on PlatformException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${strings.get('msg_could_not_open_pdf')}: ${e.message ?? e.code}'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${strings.get('msg_could_not_open_pdf')}: $e'),
          ),
        );
      }
    }
  }

  /// Opens Android SAF Storage Access Framework folder picker (`ACTION_OPEN_DOCUMENT_TREE`)
  /// returning a map with persistable 'uri' and user-friendly 'displayPath'.
  static Future<Map<String, String>?> pickCustomFolder() async {
    if (Platform.isAndroid) {
      try {
        final result = await _nativeChannel.invokeMapMethod<String, String>('pickDirectory');
        return result;
      } catch (e) {
        debugPrint('Error picking SAF folder: $e');
        return null;
      }
    }
    return null;
  }

  /// Lists all generated PDFs via native MediaStore / SAF DocumentFile / app directories.
  /// Bypasses Android 10+ scoped storage restrictions cleanly.
  static Future<List<Map<String, dynamic>>> listGeneratedPdfs(AppSettings settings) async {
    if (Platform.isAndroid) {
      try {
        final List<dynamic>? results = await _nativeChannel.invokeListMethod<dynamic>(
          'listPdfs',
          {'folderUri': settings.saveFolderUri},
        );
        if (results != null) {
          return results.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (e) {
        debugPrint('Error listing PDFs via native channel: $e');
      }
    }
    return [];
  }

  /// Deletes a PDF file via native ContentResolver (for SAF / MediaStore) or filesystem.
  static Future<bool> deletePdfFile(String path) async {
    if (Platform.isAndroid) {
      try {
        final bool? deleted = await _nativeChannel.invokeMethod<bool>('deletePdf', {'path': path});
        if (deleted == true) return true;
      } catch (e) {
        debugPrint('Error deleting PDF via native channel: $e');
      }
    }
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Reads bytes from a PDF file path or content:// URI.
  static Future<Uint8List> readPdfBytes(String path) async {
    if (Platform.isAndroid && (path.startsWith('content://') || !File(path).existsSync())) {
      try {
        final Uint8List? bytes = await _nativeChannel.invokeMethod<Uint8List>(
          'readPdfBytes',
          {'path': path},
        );
        if (bytes != null) return bytes;
      } catch (e) {
        debugPrint('Native readPdfBytes error: $e');
      }
    }
    return File(path).readAsBytes();
  }

  /// Obtains a shareable local file path for content:// URIs.
  static Future<String> getShareableFilePath(String path, String fileName) async {
    if (Platform.isAndroid && path.startsWith('content://')) {
      try {
        final String? localPath = await _nativeChannel.invokeMethod<String>(
          'getShareableFilePath',
          {'path': path, 'fileName': fileName},
        );
        if (localPath != null && localPath.isNotEmpty) {
          return localPath;
        }
      } catch (e) {
        debugPrint('Native getShareableFilePath error: $e');
      }
    }
    return path;
  }

  /// Renames a PDF file across both local filesystem and SAF content:// URIs.
  static Future<Map<String, String>?> renamePdfFile(String path, String newFileName) async {
    if (Platform.isAndroid) {
      try {
        final Map<dynamic, dynamic>? res = await _nativeChannel.invokeMethod<Map<dynamic, dynamic>>(
          'renamePdf',
          {'path': path, 'newName': newFileName},
        );
        if (res != null) {
          final String newPath = res['path']?.toString() ?? path;
          final String newName = res['name']?.toString() ?? newFileName;
          return {'path': newPath, 'name': newName};
        }
      } catch (e) {
        debugPrint('Native renamePdf fallback: $e');
      }
    }
    if (!path.startsWith('content://')) {
      final currentFile = File(path);
      final parentDir = currentFile.parent;
      final base = newFileName.endsWith('.pdf')
          ? newFileName.substring(0, newFileName.length - 4)
          : newFileName;
      String finalName = '$base.pdf';
      File targetFile = File('${parentDir.path}/$finalName');
      int counter = 1;
      while (await targetFile.exists() && targetFile.path != currentFile.path) {
        finalName = '$base($counter).pdf';
        targetFile = File('${parentDir.path}/$finalName');
        counter++;
      }
      final renamed = await currentFile.rename(targetFile.path);
      return {'path': renamed.path, 'name': finalName};
    }
    return null;
  }

  /// Overwrites an existing PDF file (both local filesystem and SAF content:// URIs).
  static Future<bool> overwritePdfBytes(String path, Uint8List bytes) async {
    if (Platform.isAndroid) {
      try {
        final bool? ok = await _nativeChannel.invokeMethod<bool>(
          'overwritePdf',
          {'path': path, 'bytes': bytes},
        );
        if (ok == true) return true;
      } catch (e) {
        debugPrint('Native overwritePdf fallback: $e');
      }
    }
    if (!path.startsWith('content://')) {
      await File(path).writeAsBytes(bytes, flush: true);
      return true;
    }
    return false;
  }

  /// Exports a single PDF file or path to `/storage/emulated/0/Download/PDF Maker/`
  /// via the native Android MediaStore / Downloads channel.
  static Future<String?> exportPdfToDownloads(dynamic sourceFileOrPath) async {
    final String sourcePath = sourceFileOrPath is File ? sourceFileOrPath.path : sourceFileOrPath.toString();
    final String fileName = sourceFileOrPath is File
        ? sourceFileOrPath.uri.pathSegments.last
        : (sourcePath.contains('/') ? sourcePath.split('/').last : 'document.pdf');
    if (Platform.isAndroid) {
      try {
        final String? exportedPath = await _nativeChannel.invokeMethod<String>(
          'exportPdfToDownloads',
          {
            'sourcePath': sourcePath,
            'fileName': fileName,
          },
        );
        if (exportedPath != null && exportedPath.isNotEmpty) {
          return exportedPath;
        }
      } catch (e) {
        debugPrint('Native exportPdfToDownloads fallback: $e');
      }
    }

    try {
      final Directory downloadsDir = Directory('/storage/emulated/0/Download/PDF Maker');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      final String targetPath = '${downloadsDir.path}/$fileName';
      final Uint8List bytes = await readPdfBytes(sourcePath);
      final File targetFile = File(targetPath);
      await targetFile.writeAsBytes(bytes);
      return targetFile.path;
    } catch (_) {
      return null;
    }
  }

  /// Batch-exports multiple PDF file paths to `/storage/emulated/0/Download/PDF Maker/`
  /// in parallel across the native worker pool. Returns the number of successfully exported files.
  static Future<int> batchExportPdfsToDownloads(Iterable<String> filePaths) async {
    final List<String> paths = filePaths.toList();
    if (paths.isEmpty) return 0;

    int exportedCount = 0;
    const int batchSize = 4;
    for (int start = 0; start < paths.length; start += batchSize) {
      final int end = min(start + batchSize, paths.length);
      final List<Future<String?>> futures = [];
      for (int i = start; i < end; i++) {
        futures.add(exportPdfToDownloads(paths[i]));
      }
      final results = await Future.wait(futures);
      for (final res in results) {
        if (res != null && res.isNotEmpty) {
          exportedCount++;
        }
      }
    }
    return exportedCount;
  }

  /// Resolves the public device storage directory:
  /// Primary target: /storage/emulated/0/Documents/PDF Maker/
  /// Files stored here reside in public shared storage and ALWAYS survive app uninstallation.
  static Future<Directory> getPdfStorageDirectory() async {
    if (Platform.isAndroid) {
      try {
        final Directory primaryDocs = Directory('/storage/emulated/0/Documents/PDF Maker');
        if (await primaryDocs.exists()) {
          return primaryDocs;
        }
        await primaryDocs.create(recursive: true);
        if (await primaryDocs.exists()) {
          return primaryDocs;
        }
      } catch (e) {
        debugPrint('Notice: direct /storage/emulated/0/Documents creation deferred to native channel: $e');
      }
      return Directory('/storage/emulated/0/Documents/PDF Maker');
    }

    final Directory docDir = await getApplicationDocumentsDirectory();
    final Directory fallback = Directory('${docDir.path}/PDF Maker');
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    return fallback;
  }

  /// Returns all search directories where generated PDFs could be located,
  /// including legacy folders for backward compatibility.
  static Future<List<Directory>> getAllPdfSearchDirectories() async {
    final List<Directory> dirs = [];
    final primary = await getPdfStorageDirectory();
    dirs.add(primary);

    if (Platform.isAndroid) {
      final legacyPro = Directory('/storage/emulated/0/Documents/PDF Maker Pro');
      if (await legacyPro.exists()) dirs.add(legacyPro);

      final legacyOld = Directory('/storage/emulated/0/Documents/PDF documents(pdf_maker)');
      if (await legacyOld.exists()) dirs.add(legacyOld);
    }

    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        for (final sub in ['PDF Maker', 'PDF Maker Pro', 'PDF documents(pdf_maker)']) {
          final d = Directory('${ext.path}/$sub');
          if (await d.exists() && !dirs.any((existing) => existing.path == d.path)) {
            dirs.add(d);
          }
        }
      }
    } catch (_) {}

    try {
      final doc = await getApplicationDocumentsDirectory();
      for (final sub in ['PDF Maker', 'PDF Maker Pro', 'PDF documents(pdf_maker)']) {
        final d = Directory('${doc.path}/$sub');
        if (await d.exists() && !dirs.any((existing) => existing.path == d.path)) {
          dirs.add(d);
        }
      }
    } catch (_) {}

    return dirs;
  }

  /// Builds the `pw.Document` and serializes `pdf.save()` inside a background isolate.
  static Future<Uint8List> _buildPdfBytesInIsolate({
    required List<_PreparedPdfPage> preparedPages,
    required bool isFreeDynamic,
  }) async {
    return Isolate.run(() async {
      final pdf = pw.Document(compress: true);

      for (final pageData in preparedPages) {
        final double imgWidth = pageData.width;
        final double imgHeight = pageData.height;
        final pw.MemoryImage pwImage = pw.MemoryImage(pageData.compressedBytes);

        final PdfPageFormat pageFormat = isFreeDynamic
            ? PdfPageFormat(imgWidth, imgHeight, marginAll: 0)
            : PdfPageFormat.a4;

        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (pw.Context context) {
              if (pageData.ocrLines.isEmpty) {
                return isFreeDynamic
                    ? pw.FullPage(
                        ignoreMargins: true,
                        child: pw.Image(pwImage, fit: pw.BoxFit.fill),
                      )
                    : pw.Center(
                        child: pw.Image(pwImage, fit: pw.BoxFit.contain),
                      );
              }

              final double pageWidth = context.page.pageFormat.availableWidth;
              final double pageHeight = context.page.pageFormat.availableHeight;

              final List<pw.Widget> stackChildren = [];
              final scaleX = pageWidth / imgWidth;
              final scaleY = pageHeight / imgHeight;

              for (final line in pageData.ocrLines) {
                final left = line.left * scaleX;
                final top = line.top * scaleY;
                final width = line.width * scaleX;
                final height = line.height * scaleY;

                stackChildren.add(
                  pw.Positioned(
                    left: left,
                    top: top,
                    child: pw.SizedBox(
                      width: width > 0 ? width : null,
                      height: height > 0 ? height : null,
                      child: pw.Text(
                        line.text,
                        style: pw.TextStyle(
                          color: const PdfColor(0, 0, 0, 0),
                          fontSize: height > 0 ? height * 0.85 : 10,
                        ),
                      ),
                    ),
                  ),
                );
              }

              if (isFreeDynamic) {
                stackChildren.add(
                  pw.Positioned(
                    left: 0,
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: pw.Image(pwImage, fit: pw.BoxFit.fill),
                  ),
                );
              } else {
                stackChildren.add(
                  pw.Center(
                    child: pw.Image(pwImage, fit: pw.BoxFit.contain),
                  ),
                );
              }

              return pw.Stack(children: stackChildren);
            },
          ),
        );
      }

      return pdf.save();
    });
  }

  /// Generates a complete PDF document using parallel hardware-accelerated native image
  /// decoding, Skia perspective rectification, and background isolate PDF serialization.
  static Future<PdfGenerationResult> generatePdf({
    required List<PdfPageItem> pages,
    required AppSettings settings,
    required bool enableOcr,
    PdfCompressionProfile compressionProfile = PdfCompressionProfile.standard,
    bool isHdQuality = false,
    Function(double progress, String status)? onProgress,
  }) async {
    final strings = AppStrings(settings.language);
    final PdfCompressionProfile effectiveProfile = isHdQuality
        ? PdfCompressionProfile.hdOriginal
        : compressionProfile;

    final int totalInputPages = pages.length;

    // 1. Build the list of page render jobs (accounting for vertical 2-page merges)
    final List<_PageRenderJob> jobs = [];
    for (int i = 0; i < totalInputPages; i++) {
      final pageItem = pages[i];
      final bool mergeNext = settings.mergePagesBetweenPages &&
          pageItem.mergedWithNext &&
          (i + 1) < totalInputPages;
      final PdfPageItem? nextItem = mergeNext ? pages[i + 1] : null;
      final int displayNum = i + 1;
      if (mergeNext) {
        i++;
      }
      jobs.add(
        _PageRenderJob(
          jobIndex: jobs.length,
          displayPageNumber: displayNum,
          primary: pageItem,
          mergedNext: nextItem,
        ),
      );
    }

    final int totalJobs = jobs.length;
    final List<CompressedPageData?> compressedResults =
        List<CompressedPageData?>.filled(totalJobs, null);

    // 2. Process and compress pages in parallel batches of 4 across the native worker pool
    const int batchSize = 4;
    int completedJobs = 0;

    for (int start = 0; start < totalJobs; start += batchSize) {
      final int end = min(start + batchSize, totalJobs);
      if (onProgress != null) {
        final int currentDisplay = jobs[start].displayPageNumber;
        final double progress = (completedJobs / (totalJobs + 1)) * (enableOcr ? 0.65 : 0.88);
        onProgress(progress.clamp(0.02, 0.88), strings.processingPage(currentDisplay, totalInputPages));
      }

      final List<Future<void>> batchFutures = [];
      for (int idx = start; idx < end; idx++) {
        final job = jobs[idx];
        batchFutures.add(() async {
          final CompressedPageData? data = await ImageProcessor.processPageForPdf(
            sourcePath: job.primary.sourcePath,
            fallbackPreviewPath: job.primary.currentPreviewPath,
            rotationDegrees: job.primary.rotationDegrees,
            cropQuad: job.primary.cropQuad,
            normalizedCropRect: job.primary.normalizedCropRect,
            profile: effectiveProfile,
            nextSourcePath: job.mergedNext?.sourcePath,
            nextFallbackPreviewPath: job.mergedNext?.currentPreviewPath,
            nextRotationDegrees: job.mergedNext?.rotationDegrees ?? 0,
            nextCropQuad: job.mergedNext?.cropQuad,
            nextNormalizedCropRect: job.mergedNext?.normalizedCropRect,
          );
          compressedResults[job.jobIndex] = data;
          completedJobs++;
          if (onProgress != null) {
            final double progress = (completedJobs / (totalJobs + 1)) * (enableOcr ? 0.65 : 0.88);
            onProgress(
              progress.clamp(0.05, 0.88),
              strings.processingPage(
                min(totalInputPages, job.displayPageNumber),
                totalInputPages,
              ),
            );
          }
        }());
      }

      await Future.wait(batchFutures);
    }

    // 3. Optional On-Device OCR extraction (lazily initialized only when enableOcr == true)
    final TextRecognizer? textRecognizer = enableOcr
        ? TextRecognizer(script: TextRecognitionScript.latin)
        : null;
    final Directory? tempDir = enableOcr ? await getTemporaryDirectory() : null;

    final List<_PreparedPdfPage> preparedPages = [];

    for (int idx = 0; idx < totalJobs; idx++) {
      final CompressedPageData? compressed = compressedResults[idx];
      if (compressed == null) continue;

      final List<_OcrLineBox> ocrLines = [];
      if (enableOcr && textRecognizer != null && tempDir != null) {
        if (onProgress != null) {
          final double ocrProgress = 0.65 + ((idx + 1) / totalJobs) * 0.25;
          onProgress(ocrProgress.clamp(0.65, 0.90), strings.runningOcrOnPage(preparedPages.length + 1));
        }
        File? tempOcrFile;
        try {
          tempOcrFile = File(
            '${tempDir.path}/ocr_tmp_${DateTime.now().microsecondsSinceEpoch}_$idx.jpg',
          );
          await tempOcrFile.writeAsBytes(compressed.bytes);
          final inputImage = InputImage.fromFilePath(tempOcrFile.path);
          final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

          for (final block in recognizedText.blocks) {
            for (final line in block.lines) {
              final rect = line.boundingBox;
              ocrLines.add(
                _OcrLineBox(
                  text: line.text,
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('OCR extraction error on page ${idx + 1}: $e');
        } finally {
          try {
            if (tempOcrFile != null && await tempOcrFile.exists()) {
              await tempOcrFile.delete();
            }
          } catch (_) {}
        }
      }

      preparedPages.add(
        _PreparedPdfPage(
          compressedBytes: compressed.bytes,
          width: compressed.width,
          height: compressed.height,
          ocrLines: ocrLines,
        ),
      );
    }

    if (textRecognizer != null) {
      await textRecognizer.close();
    }

    if (onProgress != null) {
      onProgress(0.93, strings.get('status_finalizing_pdf'));
    }

    // 4. Build PDF document & serialize bytes in a background isolate
    final bool isFreeDynamic = settings.pageSizing == PdfPageSizing.freeDynamic;
    final Uint8List pdfBytes = await _buildPdfBytesInIsolate(
      preparedPages: preparedPages,
      isFreeDynamic: isFreeDynamic,
    );

    // 5. Generate Filename: PDF_YYYYMMDD_HHMMSS.pdf
    final now = DateTime.now();
    final String timeStamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final String fileName = 'PDF_$timeStamp.pdf';

    // 6. Save to Public Device Storage or user-selected SAF folder
    File? savedFile;
    String finalPath = '';
    if (Platform.isAndroid) {
      try {
        final Map<dynamic, dynamic>? saveResult =
            await _nativeChannel.invokeMethod<Map<dynamic, dynamic>>(
          'savePdf',
          {
            'fileName': fileName,
            'bytes': pdfBytes,
            'folderUri': settings.saveFolderUri,
          },
        );
        final String? savedPath = saveResult?['path']?.toString();
        if (savedPath != null && savedPath.isNotEmpty) {
          finalPath = savedPath;
          savedFile = File(savedPath);
        }
      } catch (e) {
        debugPrint('Native savePdf fallback: $e');
      }
    }

    if (savedFile == null || finalPath.isEmpty) {
      final Directory baseDir = await getPdfStorageDirectory();
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }
      savedFile = File('${baseDir.path}/$fileName');
      await savedFile.writeAsBytes(pdfBytes);
      finalPath = savedFile.path;
    }

    return PdfGenerationResult(
      file: savedFile,
      fileName: fileName,
      pageCount: preparedPages.isNotEmpty ? preparedPages.length : totalInputPages,
      fileSizeBytes: pdfBytes.length,
      savedPath: finalPath,
    );
  }
}
