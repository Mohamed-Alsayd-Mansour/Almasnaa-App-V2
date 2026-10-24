import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceClip {
  VoiceClip({required this.bytes, required this.mimeType, required this.extension, required this.durationMs});
  final Uint8List bytes;
  final String mimeType;
  final String extension;
  final int durationMs;
}

/// تسجيل رسالة صوتية (موبايل/ويندوز: AAC .m4a — ويب: Opus .webm).
class VoiceRecorder {
  final AudioRecorder _rec = AudioRecorder();
  final Stopwatch _clock = Stopwatch();
  bool recording = false;

  static const int minMs = 800;
  static const int maxMs = 5 * 60 * 1000;

  Duration get elapsed => _clock.elapsed;

  Future<bool> start() async {
    if (recording) return true;
    if (!await _rec.hasPermission()) return false;
    String path = '';
    final RecordConfig cfg;
    if (kIsWeb) {
      cfg = const RecordConfig(encoder: AudioEncoder.opus);
    } else {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/almasnaa_${DateTime.now().millisecondsSinceEpoch}.m4a';
      cfg = const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100);
    }
    await _rec.start(cfg, path: path);
    _clock
      ..reset()
      ..start();
    recording = true;
    return true;
  }

  /// يوقف التسجيل ويعيد المقطع، أو null إن كان قصيرًا جدًا/ملغى.
  Future<VoiceClip?> stop({bool cancel = false}) async {
    if (!recording) return null;
    recording = false;
    _clock.stop();
    final ms = _clock.elapsedMilliseconds;
    final path = await _rec.stop();
    if (cancel || path == null || ms < minMs) return null;
    final bytes = await XFile(path).readAsBytes();
    return VoiceClip(
      bytes: bytes,
      mimeType: kIsWeb ? 'audio/webm' : 'audio/mp4',
      extension: kIsWeb ? 'webm' : 'm4a',
      durationMs: ms,
    );
  }

  Future<void> dispose() async {
    try {
      if (recording) await _rec.stop();
      await _rec.dispose();
    } catch (_) {}
  }
}
