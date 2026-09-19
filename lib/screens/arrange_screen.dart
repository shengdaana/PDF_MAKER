import 'package:flutter/material.dart';
import 'arrange_pages_screen.dart';

export 'arrange_pages_screen.dart';

class ArrangeScreen extends StatelessWidget {
  final List<String> initialImagePaths;

  const ArrangeScreen({super.key, this.initialImagePaths = const []});

  @override
  Widget build(BuildContext context) {
    return ArrangePagesScreen(initialImagePaths: initialImagePaths);
  }
}

