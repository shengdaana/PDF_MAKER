import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareHandlerService {
  static StreamSubscription? _intentDataStreamSubscription;

  /// Initializes listening for incoming shared photos (both warm and cold starts)
  static void init({required Function(List<String> imagePaths) onImagesReceived}) {
    // 1. For sharing images coming outside the app while the app is in the memory (Warm start)
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          final paths = value
              .where((f) => f.path.isNotEmpty)
              .map((f) => f.path)
              .toList();
          if (paths.isNotEmpty) {
            onImagesReceived(paths);
          }
        }
      },
      onError: (err) {
        debugPrint("Error receiving shared media stream: $err");
      },
    );

    // 2. For sharing images coming outside the app while the app is closed (Cold start)
    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          final paths = value
              .where((f) => f.path.isNotEmpty)
              .map((f) => f.path)
              .toList();
          if (paths.isNotEmpty) {
            onImagesReceived(paths);
          }
          // Reset initial intent so it doesn't re-trigger on subsequent app foregrounds
          ReceiveSharingIntent.instance.reset();
        }
      },
      onError: (err) {
        debugPrint("Error receiving initial shared media: $err");
      },
    );
  }

  static void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}
