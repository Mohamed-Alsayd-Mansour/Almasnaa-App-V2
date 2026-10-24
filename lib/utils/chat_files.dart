import '../models/chat.dart';

/// أنواع المرفقات المسموحة وحدودها. تطابق قيود الخادم (دالة chat_send وإعدادات bucket)،
/// والخادم هو من يفرضها فعليًا؛ هذا فقط لرسائل خطأ مبكرة ولطيفة.
class ChatFiles {
  ChatFiles._();

  static const Map<String, String> _mimeByExt = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'pdf': 'application/pdf',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };

  static List<String> get allowedExtensions => _mimeByExt.keys.toList();

  static String? mimeForName(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0) return null;
    return _mimeByExt[name.substring(i + 1).toLowerCase()];
  }

  static MsgKind kindForMime(String mime) {
    if (mime.startsWith('image/')) return MsgKind.image;
    if (mime.startsWith('audio/')) return MsgKind.audio;
    if (mime.startsWith('video/')) return MsgKind.video;
    return MsgKind.file;
  }

  static int maxBytes(MsgKind k) => switch (k) {
        MsgKind.image => 10 * 1024 * 1024,
        MsgKind.audio => 15 * 1024 * 1024,
        MsgKind.video => 50 * 1024 * 1024,
        MsgKind.file => 20 * 1024 * 1024,
        MsgKind.text => 0,
      };

  static String sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String durationLabel(int ms) {
    final s = (ms / 1000).round();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// رسالة خطأ مبكرة (أو null إن كان الملف مقبولًا).
  static String? validate(String name, int size) {
    final mime = mimeForName(name);
    if (mime == null) return 'نوع الملف غير مسموح. المسموح: صور، صوت، فيديو، PDF، DOCX.';
    final kind = kindForMime(mime);
    if (size <= 0) return 'الملف فارغ.';
    if (size > maxBytes(kind)) {
      return 'حجم الملف أكبر من المسموح (${sizeLabel(maxBytes(kind))} كحد أقصى لـ ${kind.label}).';
    }
    return null;
  }
}
