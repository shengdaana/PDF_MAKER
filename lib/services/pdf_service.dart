import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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
  /// Resolves the universal storage directory:
  /// Primary target: /storage/emulated/0/Documents/PDF Maker Pro/
  /// Robust fallbacks for sandboxed or legacy environments.
  static Future<Directory> getPdfStorageDirectory() async {
    if (Platform.isAndroid) {
      try {
        final Directory primaryDocs = Directory('/storage/emulated/0/Documents/PDF Maker Pro');
        if (await primaryDocs.exists()) {
          return primaryDocs;
        }
        await primaryDocs.create(recursive: true);
        if (await primaryDocs.exists()) {
          return primaryDocs;
        }
      } catch (e) {
        debugPrint("Notice: direct /storage/emulated/0/Documents access restricted, using fallback: $e");
      }
    }

    // Fallback 1: App external storage directory
    try {
      final Directory? extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final Directory target = Directory("${extDir.path}/PDF Maker Pro");
        if (!await target.exists()) {
          await target.create(recursive: true);
        }
        return target;
      }
    } catch (_) {}

    // Fallback 2: Standard application documents directory
    final Directory docDir = await getApplicationDocumentsDirectory();
    final Directory fallback = Directory("${docDir.path}/PDF Maker Pro");
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
      final legacyPrimary = Directory('/storage/emulated/0/Documents/PDF documents(pdf_maker)');
      if (await legacyPrimary.exists()) dirs.add(legacyPrimary);
    }

    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final legacyExt = Directory('${ext.path}/PDF documents(pdf_maker)');
        if (await legacyExt.exists() && !dirs.any((d) => d.path == legacyExt.path)) {
          dirs.add(legacyExt);
        }
      }
    } catch (_) {}

    try {
      final doc = await getApplicationDocumentsDirectory();
      final legacyDoc = Directory('${doc.path}/PDF documents(pdf_maker)');
      if (await legacyDoc.exists() && !dirs.any((d) => d.path == legacyDoc.path)) {
        dirs.add(legacyDoc);
      }
    } catch (_) {}

    return dirs;
  }

  /// Generates a complete PDF document from the given list of pages with
  /// memory-efficient processing and the universal Standard compression default.
  static Future<PdfGenerationResult> generatePdf({
    required List<PdfPageItem> pages,
    required AppSettings settings,
    required bool enableOcr,
    PdfCompressionProfile compressionProfile = PdfCompressionProfile.standard,
    bool isHdQuality = false,
    Function(double progress, String status)? onProgress,
  }) async {
    // Resolve effective compression profile
    final PdfCompressionProfile effectiveProfile = isHdQuality
        ? PdfCompressionProfile.hdOriginal
        : compressionProfile;

    final pdf = pw.Document();
    final TextRecognizer? textRecognizer = enableOcr
        ? TextRecognizer(script: TextRecognitionScript.latin)
        : null;

    final int totalPages = pages.length;

    for (int i = 0; i < totalPages; i++) {
      final pageItem = pages[i];
      final double progress = (i + 1) / (totalPages + 1);

      if (onProgress != null) {
        onProgress(progress, 'Processing page ${i + 1} of $totalPages...');
      }

      // 1. Load image and bake current adjustments in a memory-isolated scope
      final File previewFile = File(pageItem.currentPreviewPath);
      final Uint8List rawBytes = await previewFile.readAsBytes();
      final img.Image? decodedImage = img.decodeImage(rawBytes);

      if (decodedImage == null) continue;

      final double imgWidth = decodedImage.width.toDouble();
      final double imgHeight = decodedImage.height.toDouble();

      // 2. Compress image using the standard profile (~70-80% size reduction)
      final Uint8List compressedBytes = ImageProcessor.compressForPdf(
        decodedImage,
        profile: effectiveProfile,
      );
      final pw.MemoryImage pwImage = pw.MemoryImage(compressedBytes);

      // 3. OCR Layer Extraction (English, 100% on-device)
      RecognizedText? recognizedText;
      if (enableOcr && textRecognizer != null) {
        if (onProgress != null) {
          onProgress(progress, 'Running on-device OCR on page ${i + 1}...');
        }
        try {
          final inputImage = InputImage.fromFilePath(pageItem.currentPreviewPath);
          recognizedText = await textRecognizer.processImage(inputImage);
        } catch (e) {
          debugPrint("OCR extraction error on page ${i + 1}: $e");
        }
      }

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
                            // Transparent ink keeps visible document photo undisturbed
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
              // Full-bleed: zero margins, native aspect ratio
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
              // A4 Standard: fit within page maintaining aspect ratio
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
      onProgress(0.98, 'Finalizing and saving PDF...');
    }

    // 5. Generate Filename: PDF_YYYYMMDD_HHMMSS.pdf
    final now = DateTime.now();
    final String timeStamp = "${now.year}"
        "${now.month.toString().padLeft(2, '0')}"
        "${now.day.toString().padLeft(2, '0')}_"
        "${now.hour.toString().padLeft(2, '0')}"
        "${now.minute.toString().padLeft(2, '0')}"
        "${now.second.toString().padLeft(2, '0')}";
    final String fileName = "PDF_$timeStamp.pdf";

    // 6. Target Directory: /storage/emulated/0/Documents/PDF Maker Pro/
    final Directory baseDir = await getPdfStorageDirectory();
    final File pdfFile = File("${baseDir.path}/$fileName");
    final Uint8List pdfBytes = await pdf.save();
    await pdfFile.writeAsBytes(pdfBytes);

    return PdfGenerationResult(
      file: pdfFile,
      fileName: fileName,
      pageCount: totalPages,
      fileSizeBytes: pdfBytes.length,
      savedPath: pdfFile.path,
    );
  }
}
