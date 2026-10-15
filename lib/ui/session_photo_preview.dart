import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// A scan photo must not remain in Flutter's decoded image cache after its view
/// is replaced or closed. The source adapter separately owns its Blob/file.
class SessionPhotoPreview extends StatefulWidget {
  const SessionPhotoPreview({
    super.key,
    required this.bytes,
    required this.semanticLabel,
    this.height,
    this.fit = BoxFit.contain,
    this.cacheWidth,
    this.errorBuilder,
  });
  final Uint8List bytes;
  final String semanticLabel;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;
  @override
  State<SessionPhotoPreview> createState() => _SessionPhotoPreviewState();
}

class _SessionPhotoPreviewState extends State<SessionPhotoPreview> {
  late ImageProvider provider;
  void prepare() => provider = ResizeImage.resizeIfNeeded(
    widget.cacheWidth,
    null,
    MemoryImage(widget.bytes),
  );
  @override
  void initState() {
    super.initState();
    prepare();
  }

  @override
  void didUpdateWidget(SessionPhotoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.cacheWidth != widget.cacheWidth) {
      unawaited(provider.evict());
      prepare();
    }
  }

  @override
  void dispose() {
    unawaited(provider.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
    image: provider,
    semanticLabel: widget.semanticLabel,
    height: widget.height,
    fit: widget.fit,
    errorBuilder: widget.errorBuilder,
  );
}
