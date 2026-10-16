import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'session_photo_preview.dart';
import '../scan/photo_scan.dart';
import '../scan/photo_edit.dart';

class PhotoCropEditor extends StatefulWidget {
  const PhotoCropEditor({
    super.key,
    required this.source,
    required this.initial,
    required this.onApply,
    required this.onPaste,
    required this.onManual,
  });
  final PhotoImageSource source;
  final PhotoEdit initial;
  final Future<String?> Function(PhotoEdit) onApply;
  final VoidCallback onPaste, onManual;
  @override
  State<PhotoCropEditor> createState() => _PhotoCropEditorState();
}

class _PhotoCropEditorState extends State<PhotoCropEditor>
    with WidgetsBindingObserver {
  late PhotoEdit edit;
  late final List<TextEditingController> fields;
  List<String> syncedValues = [];
  String? error;
  bool busy = false;
  bool closing = false;
  bool previewFailed = false;
  int pointers = 0;
  bool multiplePointers = false;
  Offset? anchor;
  PhotoEdit? dragStart;
  bool moving = false;
  @override
  void initState() {
    super.initState();
    edit = widget.initial;
    fields = List.generate(4, (_) => TextEditingController());
    syncFields();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      close();
    }
  }

  void close() {
    if (closing || !mounted) return;
    closing = true;
    Navigator.pop(context);
  }

  void syncFields() {
    final values = [edit.left, edit.top, edit.width, edit.height];
    for (var i = 0; i < 4; i++) {
      fields[i].text = (values[i] * 100).toStringAsFixed(4);
    }
    syncedValues = fields.map((field) => field.text).toList();
  }

  PhotoEdit? readFields() {
    // Do not round a precise touch selection through its numeric display.
    if (List.generate(
      4,
      (i) => fields[i].text == syncedValues[i],
    ).every((same) => same)) {
      return edit;
    }
    final values = fields
        .map((field) => double.tryParse(field.text.replaceAll(',', '.')))
        .toList();
    if (values.any((v) => v == null || !v.isFinite)) {
      return null;
    }
    return PhotoEdit(
      left: values[0]! / 100,
      top: values[1]! / 100,
      width: values[2]! / 100,
      height: values[3]! / 100,
      quarterTurns: edit.quarterTurns,
    );
  }

  void update(PhotoEdit next) {
    setState(() {
      edit = next;
      error = null;
      syncFields();
    });
  }

  Future<void> apply() async {
    if (previewFailed) {
      setState(() => error = 'Orijinal fotoğraf gösterilemiyor. Başka fotoğraf seç.');
      return;
    }
    final value = readFields();
    if (value == null ||
        !value.isValidFor(widget.source.width, widget.source.height)) {
      setState(
        () => error = const ScanFailure(ScanFailureKind.invalidCrop).message,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    final message = await widget.onApply(value);
    if (!mounted || closing) {
      return;
    }
    if (message == null) {
      close();
    } else {
      setState(() {
        busy = false;
        error = message;
      });
    }
  }

  Widget previewError(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !previewFailed) {
        setState(() => previewFailed = true);
      }
    });
    return Center(
      child: Semantics(
        liveRegion: true,
        child: Text(
          'Orijinal fotoğraf gösterilemedi. '
          'Düzenlemeden geri dönüp başka fotoğraf seç.',
          key: const ValueKey('crop-preview-error'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Fotoğrafı düzenle'),
      leading: IconButton(
        tooltip: 'Kırpmadan geri dön',
        icon: const Icon(Icons.arrow_back),
        onPressed: close,
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          const Text(
            'Orijinal fotoğraf',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Köşeleri sürükleyerek etiketi seç. Yazıların etrafında boşluk bırak. Alanı aşağıdaki yüzdelerle de ayarlayabilirsin.',
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Etiket kırpma alanı',
            child: SizedBox(
              key: const ValueKey('crop-canvas'),
              height: MediaQuery.viewInsetsOf(context).bottom > 0
                  ? 180
                  : math.min(440, MediaQuery.sizeOf(context).height * .48),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final ratio = edit.quarterTurns.isEven
                      ? widget.source.width / widget.source.height
                      : widget.source.height / widget.source.width;
                  final width = math.min(
                    constraints.maxWidth - 48,
                    (constraints.maxHeight - 48) * ratio,
                  );
                  final height = width / ratio;
                  final image = Rect.fromLTWH(
                    (constraints.maxWidth - width) / 2,
                    (constraints.maxHeight - height) / 2,
                    width,
                    height,
                  );
                  final crop = Rect.fromLTWH(
                    image.left + edit.left * width,
                    image.top + edit.top * height,
                    edit.width * width,
                    edit.height * height,
                  );
                  Offset normalized(Offset position) => Offset(
                    ((position.dx - image.left) / width).clamp(0, 1),
                    ((position.dy - image.top) / height).clamp(0, 1),
                  );
                  void corner(String name, Offset delta) {
                    if (busy || pointers != 1 || multiplePointers) {
                      return;
                    }
                    var left = edit.left,
                        top = edit.top,
                        right = left + edit.width,
                        bottom = top + edit.height;
                    final minWidth =
                        32 /
                        (edit.quarterTurns.isEven
                            ? widget.source.width
                            : widget.source.height);
                    final minHeight =
                        32 /
                        (edit.quarterTurns.isEven
                            ? widget.source.height
                            : widget.source.width);
                    if (name.contains('left')) {
                      left = (left + delta.dx / width).clamp(
                        0,
                        right - minWidth,
                      );
                    } else {
                      right = (right + delta.dx / width).clamp(
                        left + minWidth,
                        1,
                      );
                    }
                    if (name.contains('top')) {
                      top = (top + delta.dy / height).clamp(
                        0,
                        bottom - minHeight,
                      );
                    } else {
                      bottom = (bottom + delta.dy / height).clamp(
                        top + minHeight,
                        1,
                      );
                    }
                    update(
                      PhotoEdit(
                        left: left,
                        top: top,
                        width: right - left,
                        height: bottom - top,
                        quarterTurns: edit.quarterTurns,
                      ),
                    );
                  }

                  return Listener(
                    onPointerDown: (_) {
                      pointers++;
                      if (pointers > 1) {
                        multiplePointers = true;
                        anchor = null;
                        dragStart = null;
                      }
                    },
                    onPointerUp: (_) {
                      pointers = math.max(0, pointers - 1);
                      if (pointers == 0) {
                        multiplePointers = false;
                      }
                    },
                    onPointerCancel: (_) {
                      pointers = math.max(0, pointers - 1);
                      if (pointers == 0) {
                        multiplePointers = false;
                      }
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fromRect(
                          rect: image,
                          child: RotatedBox(
                            quarterTurns: edit.quarterTurns,
                            child: SessionPhotoPreview(
                              bytes: widget.source.previewBytes,
                              fit: BoxFit.fill,
                              semanticLabel: 'Orijinal etiket fotoğrafı',
                              // Prefer Flutter's paint path, but WebKit can
                              // reject a valid PNG in its memory image codec.
                              // The fallback is the SAME source thumbnail via
                              // a browser-native <img> element, not the OCR crop.
                              errorBuilder: (context, error, stack) {
                                final url = widget.source.previewUrl;
                                if (url != null && url.startsWith('blob:')) {
                                  return Image.network(
                                    url,
                                    fit: BoxFit.fill,
                                    webHtmlElementStrategy:
                                        WebHtmlElementStrategy.prefer,
                                    errorBuilder: (context, error, stack) =>
                                        previewError(context),
                                  );
                                }
                                return previewError(context);
                              },
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: _CropDragSurface(
                            enabled: !busy,
                            onPointerDown: busy
                                ? null
                                : (details) {
                                    if (!image.contains(
                                      details.localPosition,
                                    )) {
                                      return;
                                    }
                                    anchor = normalized(details.localPosition);
                                    dragStart = edit;
                                    moving = crop.contains(
                                      details.localPosition,
                                    );
                                  },
                            onPointerMove: busy
                                ? null
                                : (details) {
                                    if (pointers != 1 ||
                                        multiplePointers ||
                                        anchor == null ||
                                        dragStart == null) {
                                      return;
                                    }
                                    final p = normalized(details.localPosition),
                                        start = dragStart!;
                                    if (moving) {
                                      update(
                                        PhotoEdit(
                                          left: (start.left + p.dx - anchor!.dx)
                                              .clamp(0, 1 - start.width),
                                          top: (start.top + p.dy - anchor!.dy)
                                              .clamp(0, 1 - start.height),
                                          width: start.width,
                                          height: start.height,
                                          quarterTurns: edit.quarterTurns,
                                        ),
                                      );
                                    } else {
                                      final l = math.min(anchor!.dx, p.dx),
                                          t = math.min(anchor!.dy, p.dy);
                                      if ((p.dx - anchor!.dx).abs() > .005 &&
                                          (p.dy - anchor!.dy).abs() > .005) {
                                        update(
                                          PhotoEdit(
                                            left: l,
                                            top: t,
                                            width: (p.dx - anchor!.dx).abs(),
                                            height: (p.dy - anchor!.dy).abs(),
                                            quarterTurns: edit.quarterTurns,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            onPointerEnd: (_) {
                              anchor = null;
                              dragStart = null;
                            },
                            child: CustomPaint(
                              painter: _CropPainter(
                                image,
                                crop,
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        for (final entry in {
                          'top-left': crop.topLeft,
                          'top-right': crop.topRight,
                          'bottom-left': crop.bottomLeft,
                          'bottom-right': crop.bottomRight,
                        }.entries)
                          Positioned(
                            left: entry.value.dx - 22,
                            top: entry.value.dy - 22,
                            width: 44,
                            height: 44,
                            child: Semantics(
                              container: true,
                              focusable: true,
                              label: switch (entry.key) {
                                'top-left' => 'Sol üst köşe',
                                'top-right' => 'Sağ üst köşe',
                                'bottom-left' => 'Sol alt köşe',
                                _ => 'Sağ alt köşe',
                              },
                              child: _CropDragSurface(
                                enabled: !busy,
                                key: ValueKey('crop-${entry.key}'),
                                onPointerMove: busy
                                    ? null
                                    : (details) =>
                                          corner(entry.key, details.delta),
                                child: Center(
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          Text(
            '${widget.source.width} × ${widget.source.height} px · ${edit.quarterTurns * 90}°',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => update(edit.rotate(-1)),
                  icon: const Icon(Icons.rotate_left),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(44, 48),
                  ),
                  label: const Text('90° sola'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => update(edit.rotate(1)),
                  icon: const Icon(Icons.rotate_right),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(44, 48),
                  ),
                  label: const Text('90° sağa'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var row = 0; row < 2; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  for (var column = 0; column < 2; column++) ...[
                    if (column > 0) const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: ValueKey(
                          [
                            'crop-left',
                            'crop-top',
                            'crop-width',
                            'crop-height',
                          ][row * 2 + column],
                        ),
                        controller: fields[row * 2 + column],
                        enabled: !busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: [
                            'Sol (%)',
                            'Üst (%)',
                            'Genişlik (%)',
                            'Yükseklik (%)',
                          ][row * 2 + column],
                        ),
                        onChanged: (_) {
                          final next = readFields();
                          if (next != null &&
                              next.isValidFor(
                                widget.source.width,
                                widget.source.height,
                              )) {
                            setState(() => edit = next);
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => update(const PhotoEdit()),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Sıfırla'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          if (busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Fotoğraf düzenleniyor…'),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy || previewFailed ? null : apply,
            child: const Text('Kırpmayı uygula'),
          ),
          TextButton(
            onPressed: close,
            child: const Text('Düzenlemeyi iptal et'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              if (!closing) {
                closing = true;
                widget.onPaste();
              }
            },
            icon: const Icon(Icons.content_paste),
            label: const Text('Metin yapıştır'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              if (!closing) {
                closing = true;
                widget.onManual();
              }
            },
            icon: const Icon(Icons.edit_note),
            label: const Text('Elle giriş'),
          ),
        ],
      ),
    ),
  );
}

/// The crop owns a gesture that starts on the photo/handles. A normal pan
/// waits for more diagonal motion than the surrounding vertical ListView,
/// which otherwise wins slow corner drags on real touch hardware.
class _CropDragSurface extends StatelessWidget {
  const _CropDragSurface({
    super.key,
    required this.enabled,
    required this.child,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerEnd,
  });
  final bool enabled;
  final Widget child;
  final void Function(PointerDownEvent)? onPointerDown;
  final void Function(PointerMoveEvent)? onPointerMove;
  final void Function(PointerEvent)? onPointerEnd;
  @override
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      if (enabled)
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              EagerGestureRecognizer.new,
              (_) {},
            ),
    },
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: onPointerDown,
      onPointerMove: onPointerMove,
      onPointerUp: onPointerEnd,
      onPointerCancel: onPointerEnd,
      child: child,
    ),
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.crop, this.color);
  final Rect image, crop;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(image)
      ..addRect(crop);
    canvas.drawPath(outside, Paint()..color = Colors.black45);
    canvas.drawRect(
      crop,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.crop != crop || old.color != color;
}
