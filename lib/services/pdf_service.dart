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
import '../utils/image_processing.dart';

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
  /// Generates a complete PDF document from the given list of pages
  static Future<PdfGenerationResult> generatePdf({
    required List<PdfPageItem> pages,
    required AppSettings settings,
    required bool enableOcr,
    required bool isHdQuality,
    Function(double progress, String status)? onProgress,
  }) async {
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

      // 1. Load image and bake current adjustments
      final File previewFile = File(pageItem.currentPreviewPath);
      final Uint8List rawBytes = await previewFile.readAsBytes();
      final img.Image? decodedImage = img.decodeImage(rawBytes);

      if (decodedImage == null) continue;

      // 2. Compress image for PDF (Standard vs HD)
      final Uint8List compressedBytes = ImageProcessingService.compressForPdf(
        decodedImage,
        isHdQuality: isHdQuality,
      );
      final pw.MemoryImage pwImage = pw.MemoryImage(compressedBytes);

      // 3. OCR Layer Extraction (English, on-device only)
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
      final double imgWidth = decodedImage.width.toDouble();
      final double imgHeight = decodedImage.height.toDouble();

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

            // A. OCR Invisible Text Layer (Positioned behind visible image)
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
                            // Invisible font color so image is visually untouched
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

            // B. Visible Image
            if (isFreeDynamic) {
              // Full-bleed: zero margins, no letterboxing, exact match
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

    // 6. Target Directory: Documents/PDF documents(pdf_maker)
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

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

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
