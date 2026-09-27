import 'dart:io';
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

class PdfService {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.introbird.pdfmakerflutter/native_files');

  /// Opens a generated PDF file using Android's FileProvider (content:// URI) and
  /// standard ACTION_VIEW intent — requires zero MANAGE_EXTERNAL_STORAGE permission (FIX 3).
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

  /// Resolves the public device storage directory (FIX 4):
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

  /// Helper that loads and processes a single PdfPageItem at full resolution.
  static Future<img.Image?> _resolveProcessedPageImage(PdfPageItem pageItem) async {
    final File sourceFile = File(pageItem.sourcePath);
    if (await sourceFile.exists()) {
      final img.Image? normalized = await ImageProcessor.loadAndNormalizeExif(sourceFile);
      if (normalized != null) {
        final bool hasEdits = pageItem.rotationDegrees % 360 != 0 ||
            pageItem.cropQuad != null ||
            pageItem.normalizedCropRect != null ||
            pageItem.enhanceMode != EnhanceMode.none;

        if (!hasEdits) {
          return normalized;
        }

        return ImageProcessor.processPipeline(
          sourceImage: normalized,
          rotationDegrees: pageItem.rotationDegrees,
          cropQuad: pageItem.cropQuad,
          normalizedCropRect: pageItem.normalizedCropRect,
          enhanceMode: pageItem.enhanceMode,
          isEnhanced: pageItem.isEnhanced,
        );
      }
    }

    // Fallback to preview file if source is unavailable
    final File previewFile = File(pageItem.currentPreviewPath);
    if (await previewFile.exists()) {
      final Uint8List rawBytes = await previewFile.readAsBytes();
      return img.decodeImage(rawBytes);
    }
    return null;
  }

  /// Vertically stitches two images into one combined page image when Merge with Next Page is active.
  static img.Image _stitchImagesVertically(img.Image top, img.Image bottom) {
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

  /// Generates a complete PDF document from the given list of pages with
  /// memory-efficient processing and saves to public device storage (FIX 4).
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

    final pdf = pw.Document();
    // 100% On-Device Offline OCR (Latin script bundled model, zero network requests - FIX 8)
    final TextRecognizer? textRecognizer = enableOcr
        ? TextRecognizer(script: TextRecognitionScript.latin)
        : null;

    final int totalPages = pages.length;
    int renderedPageCount = 0;

    for (int i = 0; i < totalPages; i++) {
      final pageItem = pages[i];
      final double progress = (i + 1) / (totalPages + 1);

      if (onProgress != null) {
        onProgress(progress, strings.processingPage(i + 1, totalPages));
      }

      // 1. Load image and bake current adjustments from clean full-res source
      img.Image? decodedImage = await _resolveProcessedPageImage(pageItem);
      if (decodedImage == null) continue;

      // Support optional vertical merge with next page
      if (settings.mergePagesBetweenPages && pageItem.mergedWithNext && (i + 1) < totalPages) {
        final img.Image? nextImage = await _resolveProcessedPageImage(pages[i + 1]);
        if (nextImage != null) {
          decodedImage = _stitchImagesVertically(decodedImage, nextImage);
          i++; // Consume merged next page
        }
      }

      // 2. Compress image using per-image profile (~1800px @ 70% for Standard)
      final Uint8List compressedBytes = ImageProcessor.compressForPdf(
        decodedImage,
        profile: effectiveProfile,
      );
      final img.Image? compressedDecoded = img.decodeImage(compressedBytes);
      final double imgWidth = (compressedDecoded ?? decodedImage).width.toDouble();
      final double imgHeight = (compressedDecoded ?? decodedImage).height.toDouble();

      final pw.MemoryImage pwImage = pw.MemoryImage(compressedBytes);

      // 3. OCR Layer Extraction (100% on-device) on the exact rendered page image
      RecognizedText? recognizedText;
      if (enableOcr && textRecognizer != null) {
        if (onProgress != null) {
          onProgress(progress, strings.runningOcrOnPage(renderedPageCount + 1));
        }
        File? tempOcrFile;
        try {
          final tempDir = await getTemporaryDirectory();
          tempOcrFile = File('${tempDir.path}/ocr_tmp_${DateTime.now().microsecondsSinceEpoch}_$i.jpg');
          await tempOcrFile.writeAsBytes(compressedBytes);
          final inputImage = InputImage.fromFilePath(tempOcrFile.path);
          recognizedText = await textRecognizer.processImage(inputImage);
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

      renderedPageCount++;

      // 4. Page Layout Mode (Free / Dynamic vs A4 Standard)
      final bool isFreeDynamic = settings.pageSizing == PdfPageSizing.freeDynamic;
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

            // A. OCR Invisible Text Layer (Positioned for copy/search capability)
            if (recognizedText != null && recognizedText.blocks.isNotEmpty) {
              final scaleX = pageWidth / imgWidth;
              final scaleY = pageHeight / imgHeight;

              for (final block in recognizedText.blocks) {
                for (final line in block.lines) {
                  final rect = line.boundingBox;
                  final left = rect.left * scaleX;
                  final top = rect.top * scaleY;
                  final width = rect.width * scaleX;
                  final height = rect.height * scaleY;

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
            }

            // B. Visible Document Photo
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

    if (textRecognizer != null) {
      await textRecognizer.close();
    }

    if (onProgress != null) {
      onProgress(0.98, strings.get('status_finalizing_pdf'));
    }

    // 5. Generate Filename: PDF_YYYYMMDD_HHMMSS.pdf
    final now = DateTime.now();
    final String timeStamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final String fileName = 'PDF_$timeStamp.pdf';

    final Uint8List pdfBytes = await pdf.save();

    // 6. Save to Public Device Storage (/storage/emulated/0/Documents/PDF Maker/) (FIX 4)
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
      pageCount: renderedPageCount > 0 ? renderedPageCount : totalPages,
      fileSizeBytes: pdfBytes.length,
      savedPath: savedFile.path,
    );
  }
}
