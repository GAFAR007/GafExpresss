/// lib/app/features/home/presentation/production/production_local_video_preview_web.dart
/// -------------------------------------------------------------------------------------
/// WHAT:
/// - Web video element preview for newly captured production proof videos.
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'package:frontend/app/features/home/presentation/production/production_models.dart';

class ProductionLocalVideoPreview extends StatefulWidget {
  final ProductionTaskProgressProofInput proof;
  final BoxFit fit;

  const ProductionLocalVideoPreview({
    super.key,
    required this.proof,
    this.fit = BoxFit.cover,
  });

  @override
  State<ProductionLocalVideoPreview> createState() =>
      _ProductionLocalVideoPreviewState();
}

class _ProductionLocalVideoPreviewState
    extends State<ProductionLocalVideoPreview> {
  late final String _viewType;
  late final web.HTMLVideoElement _video;
  String? _objectUrl;

  @override
  void initState() {
    super.initState();
    _viewType =
        "production-local-proof-video-${DateTime.now().microsecondsSinceEpoch}";
    _video = web.HTMLVideoElement()
      ..controls = true
      ..muted = true
      ..preload = "metadata"
      ..style.width = "100%"
      ..style.height = "100%"
      ..style.backgroundColor = "transparent";
    _applyVideoSource();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _video);
  }

  @override
  void didUpdateWidget(covariant ProductionLocalVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.proof, widget.proof)) {
      return;
    }
    _revokeObjectUrl();
    _applyVideoSource();
  }

  @override
  void dispose() {
    _revokeObjectUrl();
    super.dispose();
  }

  void _applyVideoSource() {
    final mimeType = _videoMimeType(widget.proof.filename);
    final blob = web.Blob(
      <web.BlobPart>[Uint8List.fromList(widget.proof.bytes).toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    _objectUrl = web.URL.createObjectURL(blob);
    _video
      ..src = _objectUrl!
      ..style.objectFit = widget.fit == BoxFit.contain ? "contain" : "cover";
  }

  void _revokeObjectUrl() {
    final objectUrl = _objectUrl;
    if (objectUrl == null) {
      return;
    }
    web.URL.revokeObjectURL(objectUrl);
    _objectUrl = null;
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

String _videoMimeType(String filename) {
  final normalized = filename.trim().toLowerCase();
  if (normalized.endsWith(".webm")) {
    return "video/webm";
  }
  if (normalized.endsWith(".mov")) {
    return "video/quicktime";
  }
  if (normalized.endsWith(".m4v")) {
    return "video/x-m4v";
  }
  return "video/mp4";
}
