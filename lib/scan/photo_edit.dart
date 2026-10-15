/// Crop fractions refer to the EXIF-normalized ORIGINAL, after quarter turns.
/// No Flutter, OCR text, parser or platform dependencies live here.
class PhotoEdit {
  const PhotoEdit({
    this.left = 0,
    this.top = 0,
    this.width = 1,
    this.height = 1,
    this.quarterTurns = 0,
  });
  final double left, top, width, height;
  final int quarterTurns;

  bool isValidFor(int sourceWidth, int sourceHeight) {
    if (sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        quarterTurns < 0 ||
        quarterTurns > 3 ||
        ![left, top, width, height].every((v) => v.isFinite) ||
        left < 0 ||
        top < 0 ||
        width <= 0 ||
        height <= 0 ||
        left + width > 1.000000001 ||
        top + height > 1.000000001) {
      return false;
    }
    final w = quarterTurns.isEven ? sourceWidth : sourceHeight;
    final h = quarterTurns.isEven ? sourceHeight : sourceWidth;
    return width * w >= 32 &&
        height * h >= 32 &&
        width * w / (height * h) <= 40 &&
        height * h / (width * w) <= 40;
  }

  PhotoEdit rotate(int turns) {
    var next = this;
    for (var n = 0; n < turns % 4; n++) {
      next = PhotoEdit(
        left: (1 - next.top - next.height).clamp(0.0, 1.0).toDouble(),
        top: next.left,
        width: next.height,
        height: next.width,
        quarterTurns: (next.quarterTurns + 1) % 4,
      );
    }
    return next;
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoEdit &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height &&
      quarterTurns == other.quarterTurns;
  @override
  int get hashCode => Object.hash(left, top, width, height, quarterTurns);
}
