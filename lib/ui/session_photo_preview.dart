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
    this.fallbackUrl,
    this.errorBuilder,
  });
  final Uint8List bytes;
  final String semanticLabel;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  /// Temporary same-session browser Blob URL for the EXACT preview image.
  /// The source adapter revokes this URL when the photo session is released.
  final String? fallbackUrl;
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

  // Some Safari/WebKit Flutter codecs reject a valid in-memory PNG even when
  // Safari's native <img> decoder can show the same pixels. Do not replace
  // the preview with a different photo or silently continue with a blank.
  Widget previewDecodeError(BuildContext context, Object error, StackTrace? stack) {
    final url = widget.fallbackUrl;
    if (url != null && url.startsWith('blob:')) {
      return Image.network(
        url,
        semanticLabel: widget.semanticLabel,
        height: widget.height,
        fit: widget.fit,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: widget.errorBuilder,
      );
    }
    return widget.errorBuilder!(context, error, stack);
  }

  @override
  Widget build(BuildContext context) => Image(
    image: provider,
    semanticLabel: widget.semanticLabel,
    height: widget.height,
    fit: widget.fit,
    errorBuilder: widget.errorBuilder != null ||
            (widget.fallbackUrl?.startsWith('blob:') ?? false)
        ? previewDecodeError
        : null,
  );
}
