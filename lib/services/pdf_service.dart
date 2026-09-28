import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
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

class PdfService {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.introbird.pdfmakerflutter/native_files');

  /// Opens a generated PDF file using Android's FileProvider (content:// URI) and
  /// standard ACTION_VIEW intent — requires zero MANAGE_EXTERNAL_STORAGE permission.
  static Future<void> openPdfFile(BuildContext context, File file) async {
    final strings = AppStateScope.of(context).strings;
    try {
      await _nativeChannel.invokeMethod('openPdf', {'path': file.path});
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

  /// Synchronous helper intended to run inside `Isolate.run`:
  /// Loads and processes a single page at full resolution.
  /// FIX 2: If the user did not rotate and did not move crop corners away from full-frame,
  /// returns the EXIF-normalized original image directly as-is without perspective warp.
  static img.Image? _resolvePageImageSync({
    required String sourcePath,
    required String fallbackPreviewPath,
    required int rotationDegrees,
    required CropQuad? cropQuad,
    required Rect? normalizedCropRect,
  }) {
    final img.Image? normalized = ImageProcessor.decodeAndNormalizeSync(sourcePath);
    if (normalized != null) {
      return ImageProcessor.processPipeline(
        sourceImage: normalized,
        rotationDegrees: rotationDegrees,
        cropQuad: cropQuad,
        normalizedCropRect: normalizedCropRect,
      );
    }

    final previewFile = File(fallbackPreviewPath);
    if (previewFile.existsSync()) {
      final Uint8List rawBytes = previewFile.readAsBytesSync();
      return img.decodeImage(rawBytes);
    }
    return null;
  }

  /// Vertically stitches two images into one combined page image when Merge with Next Page is active.
  static img.Image _stitchImagesVerticallySync(img.Image top, img.Image bottom) {
    final int targetWidth = top.width >= bottom.width ? top.width : bottom.width;
    final img.Image topScaled = top.width == targetWidth
        ? top
        : img.copyResize(top, width: targetWidth, interpolation: img.Interpolation.linear);
    final img.Image bottomScaled = bottom.width == targetWidth
        ? bottom
        : img.copyResize(bottom, width: targetWidth, interpolation: img.Interpolation.linear);

    const int gap = 12;
    final int totalHeight = topScaled.height + gap + bottomScaled.height;
    final img.Image combined = img.Image(width: targetWidth, height: totalHeight);
    img.fill(combined, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(combined, topScaled, dstX: 0, dstY: 0);
    img.compositeImage(combined, bottomScaled, dstX: 0, dstY: topScaled.height + gap);
    return combined;
  }

  /// Processes and compresses a single page (and optional merged next page) inside a background isolate (FIX 3).
  static Future<CompressedPageData?> _processAndCompressPageInIsolate({
    required String sourcePath,
    required String fallbackPreviewPath,
    required int rotationDegrees,
    required CropQuad? cropQuad,
    required Rect? normalizedCropRect,
    required PdfCompressionProfile profile,
    String? nextSourcePath,
    String? nextFallbackPreviewPath,
    int nextRotationDegrees = 0,
    CropQuad? nextCropQuad,
    Rect? nextNormalizedCropRect,
  }) async {
    return Isolate.run(() {
      img.Image? pageImage = _resolvePageImageSync(
        sourcePath: sourcePath,
        fallbackPreviewPath: fallbackPreviewPath,
        rotationDegrees: rotationDegrees,
        cropQuad: cropQuad,
        normalizedCropRect: normalizedCropRect,
      );
      if (pageImage == null) return null;

      if (nextSourcePath != null && nextFallbackPreviewPath != null) {
        final img.Image? nextImage = _resolvePageImageSync(
          sourcePath: nextSourcePath,
          fallbackPreviewPath: nextFallbackPreviewPath,
          rotationDegrees: nextRotationDegrees,
          cropQuad: nextCropQuad,
          normalizedCropRect: nextNormalizedCropRect,
        );
        if (nextImage != null) {
          pageImage = _stitchImagesVerticallySync(pageImage, nextImage);
        }
      }

      // Compress and return dimensions directly without re-decoding the JPEG (FIX 3)
      return ImageProcessor.compressForPdfWithDimensions(pageImage, profile: profile);
    });
  }

  /// Builds the `pw.Document` and serializes `pdf.save()` inside a background isolate (FIX 3).
  static Future<Uint8List> _buildPdfBytesInIsolate({
    required List<_PreparedPdfPage> preparedPages,
    required bool isFreeDynamic,
  }) async {
    return Isolate.run(() async {
      final pdf = pw.Document();

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
              final double pageWidth = context.page.pageFormat.availableWidth;
              final double pageHeight = context.page.pageFormat.availableHeight;

              final List<pw.Widget> stackChildren = [];

              if (pageData.ocrLines.isNotEmpty) {
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

  /// Generates a complete PDF document with all heavy image decoding, perspective warping,
  /// compression, and PDF serialization offloaded to background isolates (FIX 2 & FIX 3).
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

    // Lazily initialize on-device OCR only when generating a PDF with OCR enabled (FIX 3)
    final TextRecognizer? textRecognizer = enableOcr
        ? TextRecognizer(script: TextRecognitionScript.latin)
        : null;

    final int totalPages = pages.length;
    final List<_PreparedPdfPage> preparedPages = [];
    final Directory tempDir = await getTemporaryDirectory();

    for (int i = 0; i < totalPages; i++) {
      final pageItem = pages[i];
      final double progress = (i + 1) / (totalPages + 1);

      if (onProgress != null) {
        onProgress(progress, strings.processingPage(i + 1, totalPages));
      }

      final bool mergeNext =
          settings.mergePagesBetweenPages && pageItem.mergedWithNext && (i + 1) < totalPages;
      final PdfPageItem? nextItem = mergeNext ? pages[i + 1] : null;
      if (mergeNext) {
        i++; // Consume merged next page
      }

      // 1. Decode, EXIF-normalize, apply rotation/crop (only if edited), and compress in Isolate (FIX 2 & FIX 3)
      final CompressedPageData? compressed = await _processAndCompressPageInIsolate(
        sourcePath: pageItem.sourcePath,
        fallbackPreviewPath: pageItem.currentPreviewPath,
        rotationDegrees: pageItem.rotationDegrees,
        cropQuad: pageItem.cropQuad,
        normalizedCropRect: pageItem.normalizedCropRect,
        profile: effectiveProfile,
        nextSourcePath: nextItem?.sourcePath,
        nextFallbackPreviewPath: nextItem?.currentPreviewPath,
        nextRotationDegrees: nextItem?.rotationDegrees ?? 0,
        nextCropQuad: nextItem?.cropQuad,
        nextNormalizedCropRect: nextItem?.normalizedCropRect,
      );

      if (compressed == null) continue;

      // 2. Optional On-Device OCR extraction
      final List<_OcrLineBox> ocrLines = [];
      if (enableOcr && textRecognizer != null) {
        if (onProgress != null) {
          onProgress(progress, strings.runningOcrOnPage(preparedPages.length + 1));
        }
        File? tempOcrFile;
        try {
          tempOcrFile = File(
            '${tempDir.path}/ocr_tmp_${DateTime.now().microsecondsSinceEpoch}_$i.jpg',
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
          debugPrint('OCR extraction error on page ${i + 1}: $e');
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
      onProgress(0.95, strings.get('status_finalizing_pdf'));
    }

    // 3. Build PDF document & serialize bytes in a background isolate (FIX 3)
    final bool isFreeDynamic = settings.pageSizing == PdfPageSizing.freeDynamic;
    final Uint8List pdfBytes = await _buildPdfBytesInIsolate(
      preparedPages: preparedPages,
      isFreeDynamic: isFreeDynamic,
    );

    // 4. Generate Filename: PDF_YYYYMMDD_HHMMSS.pdf
    final now = DateTime.now();
    final String timeStamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final String fileName = 'PDF_$timeStamp.pdf';

    // 5. Save to Public Device Storage (/storage/emulated/0/Documents/PDF Maker/)
    File? savedFile;
    if (Platform.isAndroid) {
      try {
        final String? savedPath = await _nativeChannel.invokeMethod<String>(
          'savePdfToPublicDocuments',
          {
            'fileName': fileName,
            'bytes': pdfBytes,
          },
        );
        if (savedPath != null && savedPath.isNotEmpty) {
          savedFile = File(savedPath);
        }
      } catch (e) {
        debugPrint('Native savePdfToPublicDocuments fallback: $e');
      }
    }

    if (savedFile == null) {
      final Directory baseDir = await getPdfStorageDirectory();
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }
      savedFile = File('${baseDir.path}/$fileName');
      await savedFile.writeAsBytes(pdfBytes);
    }

    return PdfGenerationResult(
      file: savedFile,
      fileName: fileName,
      pageCount: preparedPages.isNotEmpty ? preparedPages.length : totalPages,
      fileSizeBytes: pdfBytes.length,
      savedPath: savedFile.path,
    );
  }
}
