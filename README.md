# PDF Maker

[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)](#)
[![Framework](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](#)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](#license)
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20Offline%20%7C%20No%20Internet%20Permission-success)](#privacy--security-model)

**PDF Maker** (`com.introbird.pdfmakerflutter`) is a fast, 100% offline Android utility that converts camera photos and gallery images into clean, high-clarity, searchable PDFs. Built with Flutter and a hardware-accelerated native Android image pipeline (`BitmapFactory` + Skia `Matrix.setPolyToPoly`), it delivers instant 4-corner perspective straightening, multi-core parallel PDF generation, on-device OCR text indexing, and persistent public storage that survives app uninstallation.

---

## Key Features

### 1. Fast Photo Import & System Share Integration
- **Multi-Photo Picker:** Select dozens of photos at once from your device gallery.
- **System Share Target (`Share → PDF Maker`):** Select images directly inside any Android Gallery or File Manager app and share them straight to **PDF Maker** (`ACTION_SEND` / `ACTION_SEND_MULTIPLE`).
- **Parallel Hardware-Accelerated Thumbnails:** Generates lightweight 960px EXIF-normalized working previews in parallel across CPU cores (`~20ms` per photo) so list scrolling and editing run at a locked 60 FPS without decoding full 12MP–48MP camera images on the UI thread.

### 2. 4-Corner Manual Perspective Crop & Auto-Flatten
- **Interactive 4-Corner Handle Canvas:** Drag each corner independently with a real-time **magnifying loupe** in the opposite corner for pixel-accurate document edge placement.
- **Unconditional Perspective Straightening on Confirm:** Moving any corner away from the default full-frame and tapping **Confirm** automatically warps and flattens the quadrilateral using Android's native Skia C++ `Matrix.setPolyToPoly` homography while preserving the true Euclidean edge-length aspect ratio.
- **Zero-Loss Passthrough for Untouched Pages:** If the 4 corners are left at their default full-frame position (`[0.0 .. 1.0]`), perspective warping is bypassed completely so untouched photos retain their exact original pixels without unnecessary re-encoding.
- **90° Clockwise Rotation & One-Tap Reset:** Rotate pages in 90° increments or reset the crop quad to full-frame in a single tap.

### 3. Page Arrangement, Merging & Batch Page Deletion
- **Hero Page Cards:** High-visibility page cards with page numbering, quick delete with **UNDO**, and optional `▲` / `▼` reorder arrows.
- **Vertical 2-Page Merge:** Enable *"Merge with Next Page"* to stitch two consecutive photos vertically onto a single PDF page (ideal for front-and-back ID cards or receipts).
- **Batch Page Selection & Deletion:** Long-press any page card (or tap the checklist icon in the toolbar) to select multiple pages, **Select All**, and **Delete Selected** pages in one action with full **UNDO** support.

### 4. Flexible PDF Quality, Page Sizing & On-Device OCR
- **Quality Presets:**
  - **Standard Quality (Recommended):** `~1800px` max dimension at `70%` JPEG quality — crisp text and compact file size for WhatsApp and email.
  - **HD Original Quality:** Up to `3200px` at `90%` quality for printing and archival.
  - **Always Ask:** Prompt for Standard vs. HD each time you tap **Create PDF Now**.
- **Page Sizing Modes:**
  - **Original Photo Size (No Borders):** Each PDF page dynamically matches the exact aspect ratio of its photo with zero white margins.
  - **A4 Standard Size:** Centers each image on a standard A4 sheet for printing.
- **On-Device Searchable OCR:** Optional offline text recognition embeds an invisible, selectable, and searchable text layer aligned with detected text bounding boxes.

### 5. Built-in PDF Library, Editor & Batch File Operations
- **See Generated PDFs:** Browse all saved PDFs grouped chronologically (*Today*, *Yesterday*, weekday, or date) with instant filename search.
- **Batch Export, Batch Share & Batch Delete:**
  - Enter multi-select mode via the toolbar checklist button or by long-pressing any PDF card.
  - **Batch Export to Downloads:** Save copies of all selected PDFs to `/storage/emulated/0/Download/PDF Maker/` in one tap.
  - **Batch Share:** Share multiple PDFs simultaneously to WhatsApp, Gmail, Drive, or Bluetooth.
  - **Batch Delete:** Permanently remove multiple selected PDFs with confirmation.
- **Built-in PDF Detail & Page Editor:** Preview individual pages of any existing PDF, rename files, add more photos, reorder/rotate/crop pages, or save changes as a new copy or in-place.
- **Zero-Permission External Viewer Launching:** Opens PDFs in any installed PDF reader using Android `FileProvider` (`content://` URI + `FLAG_GRANT_READ_URI_PERMISSION`) without requiring `MANAGE_EXTERNAL_STORAGE`.

### 6. Persistent Public Storage (Survives App Uninstallation)
- Generated PDFs are written directly to public shared storage at:
  - **Primary Folder:** `/storage/emulated/0/Documents/PDF Maker/`
  - **Export Folder:** `/storage/emulated/0/Download/PDF Maker/`
- Files are indexed immediately via `MediaScannerConnection` / `MediaStore` and **never** deleted if the user uninstalls the app.

### 7. Trilingual Localization & Accessible Material 3 Themes
- **100% Translated UI:** Switch instantaneously between:
  - **English** (Default)
  - **Everyday Hindi — हिंदी (आम बोलचाल की भाषा)**
  - **Hinglish (Bolchal wali Hindi)**
- **5 Color Palettes + Dark Mode:** Indigo Blue, Forest Green, Deep Purple, Rose Pink, and High-Contrast Dark.

---

## Performance & Architecture

To eliminate UI jank and make cropping and PDF generation instantaneous even on 50+ page documents, **PDF Maker** uses a hybrid architecture combining Flutter's reactive UI with native Android C++/Skia image processing:

| Stage | Optimization Implemented | Typical Latency |
| :--- | :--- | :--- |
| **Gallery Import** | Parallel batches of 4 via native `BitmapFactory.Options.inSampleSize` subsampling + `ExifInterface` orientation matrix | `~20–30 ms` / photo |
| **Opening Crop Screen** | Native `loadEditPreview` fast-path reads pre-downsampled `960px` thumbnail bytes & bounds directly without re-encoding JPEG | `~5–12 ms` |
| **Dragging Crop Corners** | `ValueNotifier<_CropDragState>` triggers `CustomPainter` canvas repaints directly without rebuilding any parent widgets | `< 2 ms` (60/120 FPS) |
| **Confirming Crop / Rotate** | Native Skia `Matrix.setPolyToPoly` 4-point homography warp + bilinear filtering on a background thread pool | `~30–45 ms` |
| **PDF Page Compression** | Parallel batches of 4 on native multi-core `Executors.newFixedThreadPool` (`processPageForPdf`) | `~35–50 ms` / page |
| **PDF Serialization** | Offloaded to a background Dart isolate (`Isolate.run`) with direct baseline JPEG stream embedding | `~80–180 ms` |
| **Library Directory Scan** | Asynchronous directory listing and `statSync()` metadata collection inside `Isolate.run` | `< 15 ms` |

---

## Project Structure

```text
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml                  # Scoped permissions, Share intent-filters, FileProvider
│       ├── kotlin/com/introbird/pdfmakerflutter/
│       │   └── MainActivity.kt                  # Native MethodChannel: Skia crop, BitmapFactory pool, MediaStore save/export, FileProvider viewer
│       └── res/xml/file_paths.xml               # FileProvider paths for Documents & Downloads
├── lib/
│   ├── main.dart                                # App entrypoint, Material 3 themes, bounded imageCache, AppStateScope
│   ├── models/
│   │   ├── app_settings.dart                    # Persistent settings & complete English / Hindi / Hinglish string tables
│   │   └── pdf_page_item.dart                   # Page model & normalized 4-corner CropQuad
│   ├── screens/
│   │   ├── home_screen.dart                     # Main launcher screen & Share intent listener
│   │   ├── arrange_pages_screen.dart            # Hero page cards, reorder, merge, batch page delete, PDF creation
│   │   ├── edit_screen.dart                     # 4-corner perspective crop & 90° rotation screen
│   │   ├── generated_pdfs_screen.dart           # Saved PDFs library, search, batch export/share/delete
│   │   ├── pdf_detail_screen.dart               # PDF page preview strip, rename, share, delete, edit entry
│   │   ├── pdf_editor_screen.dart               # Existing PDF page editor (rasterize, crop, rotate, reorder, save)
│   │   ├── settings_screen.dart                 # Theme, language, page sizing, quality preset, and privacy info
│   │   └── success_screen.dart                  # Post-generation summary with share, open, and rename actions
│   ├── services/
│   │   ├── pdf_service.dart                     # Parallel page pipeline, on-device OCR, isolate PDF builder, public storage & batch export
│   │   └── share_handler_service.dart           # Incoming Android Share intent stream handler
│   ├── utils/
│   │   └── image_processor.dart                 # Native Android bridge + pure-Dart Isolate fallback & temp cache cleaner
│   └── views/
│       └── crop_overlay_widget.dart             # 4-corner interactive crop canvas with magnifying loupe
└── pubspec.yaml
```

---

## Privacy & Security Model

- **Zero Internet Access:** Does **not** request `android.permission.INTERNET`. The app cannot transmit photos, text, or analytics over the network under any circumstance.
- **No Broad Storage Permissions:** Does **not** request `MANAGE_EXTERNAL_STORAGE`. Uses standard Android photo picker / media permissions, `MediaStore` for public `Documents` and `Downloads` persistence, and `androidx.core.content.FileProvider` for viewing PDFs.
- **Automatic Cache Hygiene:** Temporary working thumbnails are stored in the app cache directory and automatically purged when older than 2 hours.

---

## Getting Started & Building

### Prerequisites
- **Flutter SDK:** `>=3.2.0 <4.0.0`
- **JDK:** Java 17
- **Android SDK:** Compile SDK 36 / Target SDK 35

### Run in Debug Mode
```bash
flutter pub get
flutter run
```

### Build Release APK
```bash
flutter build apk --release
```
The signed release APK is output to `build/app/outputs/flutter-apk/app-release.apk`.

---

## Open-Source Dependencies & Licensing

This project is licensed under the **Apache License 2.0**.

| Package | Purpose | License |
| :--- | :--- | :--- |
| `pdf` / `printing` | PDF document generation & page rasterization | Apache-2.0 |
| `image` | Fallback isolate image manipulation | MIT |
| `image_picker` | Android gallery multi-image selection | Apache-2.0 / BSD |
| `receive_sharing_intent` | Handling `Share → PDF Maker` intents | MIT |
| `share_plus` | Sharing single and batch PDF files | BSD-3-Clause |
| `path_provider` | Temporary & application directory resolution | BSD-3-Clause |
| `shared_preferences` | Local persistence for user settings | BSD-3-Clause |
| `permission_handler` | Runtime permission requests | MIT |
| `google_mlkit_text_recognition` | Offline on-device Latin OCR text recognition* | MIT (Wrapper) |

> \* **Note for F-Droid Maintainers:** While the `google_mlkit_text_recognition` Flutter plugin wrapper is MIT-licensed and runs 100% offline on-device without Google Play Services telemetry or cloud calls, its underlying `com.google.mlkit:text-recognition` Maven artifact contains prebuilt Google ML Kit binaries. For strict F-Droid main-repository builds that require compiling all native code from source, swap the OCR step in `lib/services/pdf_service.dart` with a Tesseract FFI binding or disable OCR.
