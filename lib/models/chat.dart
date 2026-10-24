import 'dart:typed_data';

import '../auth/app_user.dart';

enum ChatKind { direct, group }

enum MsgKind {
  text,
  audio,
  image,
  video,
  file;

  static MsgKind fromDb(String v) => MsgKind.values.firstWhere((e) => e.name == v, orElse: () => MsgKind.text);

  String get label => switch (this) {
        MsgKind.text => 'نص',
        MsgKind.audio => 'رسالة صوتية',
        MsgKind.image => 'صورة',
        MsgKind.video => 'فيديو',
        MsgKind.file => 'ملف',
      };
}

/// مستخدم في دليل المحادثات (نشط فقط).
class ChatUser {
  const ChatUser({required this.id, required this.displayName, required this.role});
  final String id;
  final String displayName;
  final AppRole role;

  factory ChatUser.fromMap(Map<String, dynamic> m) => ChatUser(
        id: m['id'] as String,
        displayName: m['display_name'] as String,
        role: AppRole.fromDb(m['role'] as String),
      );
}

class ChatMember {
  const ChatMember({required this.userId, required this.lastReadAt, required this.leftAt});
  final String userId;
  final DateTime lastReadAt;
  final DateTime? leftAt;
  bool get isActive => leftAt == null;
}

class ChatConversation {
  ChatConversation({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdBy,
    required this.createdAt,
    required this.lastMessageAt,
    required this.members,
  });

  final String id;
  final ChatKind kind;
  final String? title;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final List<ChatMember> members;

  bool get isGroup => kind == ChatKind.group;
  List<ChatMember> get activeMembers => members.where((m) => m.isActive).toList();
  DateTime get sortTime => lastMessageAt ?? createdAt;

  factory ChatConversation.fromRow(Map<String, dynamic> r) => ChatConversation(
        id: r['id'] as String,
        kind: (r['kind'] as String) == 'group' ? ChatKind.group : ChatKind.direct,
        title: r['title'] as String?,
        createdBy: r['created_by'] as String,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        lastMessageAt: r['last_message_at'] == null ? null : DateTime.parse(r['last_message_at'] as String).toLocal(),
        members: ((r['chat_members'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .map((m) => ChatMember(
                  userId: m['user_id'] as String,
                  lastReadAt: DateTime.parse(m['last_read_at'] as String).toLocal(),
                  leftAt: m['left_at'] == null ? null : DateTime.parse(m['left_at'] as String).toLocal(),
                ))
            .toList(),
      );
}

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.durationMs,
  });
  final String id;
  final String path;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final int? durationMs;

  factory ChatAttachment.fromRow(Map<String, dynamic> r) => ChatAttachment(
        id: r['id'] as String,
        path: r['storage_path'] as String,
        fileName: r['file_name'] as String,
        mimeType: r['mime_type'] as String,
        sizeBytes: (r['size_bytes'] as num).toInt(),
        durationMs: (r['duration_ms'] as num?)?.toInt(),
      );
}

enum SendState { sent, sending, failed }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.attachments = const [],
    this.mentionIds = const [],
    this.state = SendState.sent,
    this.error,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final MsgKind kind;
  final String? body;
  final DateTime createdAt;
  final List<ChatAttachment> attachments;
  final List<String> mentionIds;
  final SendState state;
  final String? error;

  factory ChatMessage.fromRow(Map<String, dynamic> r) => ChatMessage(
        id: r['id'] as String,
        conversationId: r['conversation_id'] as String,
        senderId: r['sender_id'] as String,
        senderName: r['sender_name'] as String,
        kind: MsgKind.fromDb(r['kind'] as String),
        body: r['body'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        attachments: ((r['chat_attachments'] as List?) ?? const [])
            .map((e) => ChatAttachment.fromRow(Map<String, dynamic>.from(e as Map)))
            .toList(),
        mentionIds: ((r['chat_mentions'] as List?) ?? const [])
            .map((e) => (e as Map)['user_id'] as String)
            .toList(),
      );
}

/// مرفق جاهز للرفع (محفوظ في الذاكرة ليُعاد إرساله بنفس المعرّفات عند الفشل).
class PendingAttachment {
  PendingAttachment({
    required this.id,
    required this.messageId,
    required this.conversationId,
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.kind,
    this.durationMs,
  });

  final String id;
  final String messageId;
  final String conversationId;
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final MsgKind kind;
  final int? durationMs;

  /// <conversation>/<message>/<attachment>_<اسم آمن> — يطابق سياسات Storage ودالة chat_send.
  String get storagePath {
    final dot = fileName.lastIndexOf('.');
    final ext = dot >= 0 ? fileName.substring(dot).toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '') : '';
    final base = (dot >= 0 ? fileName.substring(0, dot) : fileName)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safe = base.length > 40 ? base.substring(0, 40) : base;
    return '$conversationId/$messageId/${id}_${safe.isEmpty ? 'file' : safe}$ext';
  }
}
