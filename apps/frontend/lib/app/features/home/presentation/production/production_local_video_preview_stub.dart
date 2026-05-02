/// lib/app/features/home/presentation/production/production_local_video_preview_stub.dart
/// -------------------------------------------------------------------------------------
/// WHAT:
/// - Non-web fallback for local proof video preview.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/production/production_models.dart';

class ProductionLocalVideoPreview extends StatelessWidget {
  final ProductionTaskProgressProofInput proof;
  final BoxFit fit;

  const ProductionLocalVideoPreview({
    super.key,
    required this.proof,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          color: colorScheme.primary,
          size: 30,
        ),
      ),
    );
  }
}
