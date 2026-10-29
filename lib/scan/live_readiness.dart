import '../domain/label_parser.dart';

/// Live camera cues are unverified OCR hints, never accepted garment data.
/// No frame image, EXIF, raw text, or score is kept by this tracker.
enum LiveReadinessLevel { searching, partial, readyToCapture }

class LiveFrameSample {
  const LiveFrameSample({
    required this.sequence,
    required this.ocrText,
    required this.imageQualityOk,
    required this.wholeLabelVisible,
  });

  /// Monotonically increasing ID from a *new* camera frame, not an OCR retry.
  final int sequence;
  final String ocrText;
  /// Must be measured on the current frame, never assumed to be true.
  final bool imageQualityOk;
  /// Must be established by the camera UI/visibility detector.
  /// Do not silently pass true when coverage is unknown.
  final bool wholeLabelVisible;
}

class LiveFiberCue {
  const LiveFiberCue({
    required this.section,
    required this.fiber,
    required this.percentage,
  });
  final String section;
  final String fiber;
  final num percentage;
}

/// Read-only, unverified on-screen hints; no raw OCR text is retained.
class LiveReadiness {
  LiveReadiness({
    required this.level,
    required this.message,
    required Iterable<LiveFiberCue> detectedPairs,
    required this.stableFrames,
  }) : detectedPairs = List<LiveFiberCue>.unmodifiable(detectedPairs);

  final LiveReadinessLevel level;
  final String message;
  final List<LiveFiberCue> detectedPairs;
  final int stableFrames;

  /// Green only means a potentially readable capture, not verified content.
  bool get isReadyToCapture => level == LiveReadinessLevel.readyToCapture;
}

class LiveReadinessTracker {
  LiveReadinessTracker({this.requiredStableFrames = 3}) {
    if (requiredStableFrames < 2) {
      throw ArgumentError.value(requiredStableFrames, 'requiredStableFrames',
          'At least two independent camera frames are required');
    }
  }

  final int requiredStableFrames;
  int? _lastSequence;
  String? _lastFingerprint;
  int _stableFrames = 0;
  LiveReadiness _result = LiveReadiness(
    level: LiveReadinessLevel.searching,
    message: 'Etiketi kameraya getir.',
    detectedPairs: const [],
    stableFrames: 0,
  );

  LiveReadiness get current => _result;

  /// Call only with a newly processed frame. Repeated or stale results cannot
  /// increment stability; nothing here approves or persists a composition.
  LiveReadiness observe(LiveFrameSample sample) {
    if (_lastSequence != null && sample.sequence <= _lastSequence!) {
      return _result;
    }
    _lastSequence = sample.sequence;
    if (sample.ocrText.trim().isEmpty) {
      _resetStability();
      return _set(LiveReadinessLevel.searching,
          'Yazı algılanmadı. Etiketi yaklaştırıp netleştir.', const []);
    }

    final parsed = parseLabel(sample.ocrText);
    final pairs = <LiveFiberCue>[
      for (final section in parsed.sections)
        for (final fiber in section.fibers)
          if (fiber.name != null &&
              fiber.percent != null &&
              fiber.issues.isEmpty)
            LiveFiberCue(
              section: section.name,
              fiber: fiber.name!,
              percentage: fiber.percent!,
            ),
    ];

    if (!sample.imageQualityOk) {
      _resetStability();
      return _set(LiveReadinessLevel.partial,
          'Görüntüyü sabitle, odak ve ışığı düzelt.', pairs);
    }
    if (!sample.wholeLabelVisible) {
      _resetStability();
      return _set(LiveReadinessLevel.partial,
          'Etiketin tamamını kadraja al.', pairs);
    }
    // The parser rejects missing/unknown ratios, malformed numbers, unknown
    // sections and non-100% section totals. No guessing or auto-completion.
    if (!parsed.isValid || pairs.isEmpty) {
      _resetStability();
      return _set(LiveReadinessLevel.partial,
          'Bazı yazılar görüldü; yüzde ve elyaf eşleşmesini netleştir.', pairs);
    }

    final fingerprint = parsed.sections
        .map((section) => section.name + ':' +
            section.fibers.map((fiber) =>
                fiber.name! + '=' + fiber.percent.toString()).join(','))
        .join('|');
    if (fingerprint == _lastFingerprint) {
      _stableFrames++;
    } else {
      _lastFingerprint = fingerprint;
      _stableFrames = 1;
    }
    if (_stableFrames < requiredStableFrames) {
      return _set(LiveReadinessLevel.partial,
          'Yüzde ve elyaf adayları algılandı. Kamerayı sabit tut.', pairs);
    }
    return _set(LiveReadinessLevel.readyToCapture,
        'Yazılar okunabilir görünüyor. Fotoğraf sonrası doğrula.', pairs);
  }

  void reset() {
    _lastSequence = null;
    _resetStability();
    _result = LiveReadiness(
      level: LiveReadinessLevel.searching,
      message: 'Etiketi kameraya getir.',
      detectedPairs: const [],
      stableFrames: 0,
    );
  }

  void _resetStability() {
    _lastFingerprint = null;
    _stableFrames = 0;
  }

  LiveReadiness _set(
      LiveReadinessLevel level, String message, List<LiveFiberCue> pairs) {
    _result = LiveReadiness(
      level: level,
      message: message,
      detectedPairs: pairs,
      stableFrames: _stableFrames,
    );
    return _result;
  }
}
