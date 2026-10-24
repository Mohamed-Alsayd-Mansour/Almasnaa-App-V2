import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supa.dart';
import '../models/chat.dart';

class ChatException implements Exception {
  ChatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// المحادثات على الخادم. كل الكتابة عبر دوال الخادم (chat_*) التي تتحقق من العضوية والمرفقات
/// وتمنع التكرار؛ القراءة محمية بـ RLS (العضو فقط).
class ChatRepository {
  static const String bucket = 'chat-attachments';
  static const int pageSize = 40;

  final Map<String, ({String url, DateTime expires})> _urlCache = {};

  /// رسائل الخادم (RAISE EXCEPTION) تُترجم لرسائل عربية مفهومة.
  String _arabic(Object e) {
    final raw = e is PostgrestException ? e.message : e.toString();
    final m = raw.toLowerCase();
    if (m.contains('not a member')) return 'لست عضوًا في هذه المحادثة.';
    if (m.contains('too large')) return 'حجم الملف أكبر من المسموح لهذا النوع.';
    if (m.contains('not allowed')) return 'نوع الملف غير مسموح.';
    if (m.contains('not uploaded')) return 'لم يكتمل رفع الملف. أعد المحاولة.';
    if (m.contains('too long')) return 'الرسالة طويلة جدًا (الحد 4000 حرف).';
    if (m.contains('empty message')) return 'لا يمكن إرسال رسالة فارغة.';
    if (m.contains('group title')) return 'عنوان المجموعة من 1 إلى 80 حرفًا.';
    if (m.contains('at least one member')) return 'أضف عضوًا واحدًا على الأقل.';
    if (m.contains('only group')) return 'لا يمكن مغادرة محادثة فردية.';
    if (m.contains('choose another user')) return 'اختر مستخدمًا آخر.';
    return friendlyError(e);
  }

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ChatException(_arabic(e));
    }
  }

  Future<List<ChatUser>> directory() => _guard(() async {
        final rows = await supa.rpc('chat_directory') as List;
        return rows.map((e) => ChatUser.fromMap(Map<String, dynamic>.from(e as Map))).toList();
      });

  Future<List<ChatConversation>> conversations() => _guard(() async {
        final rows = await supa
            .from('chat_conversations')
            .select('id, kind, title, created_by, created_at, last_message_at, chat_members(user_id, last_read_at, left_at)')
            .order('last_message_at', ascending: false, nullsFirst: false);
        return rows.map((r) => ChatConversation.fromRow(Map<String, dynamic>.from(r))).toList();
      });

  Future<Map<String, int>> unread() => _guard(() async {
        final rows = await supa.rpc('chat_unread') as List;
        return {for (final r in rows) (r as Map)['conversation_id'] as String: ((r['unread'] as num?) ?? 0).toInt()};
      });

  Future<String> openDirect(String userId) =>
      _guard(() async => (await supa.rpc('chat_open_direct', params: {'p_user': userId})) as String);

  Future<String> createGroup(String title, List<String> members) => _guard(() async =>
      (await supa.rpc('chat_create_group', params: {'p_title': title, 'p_members': members})) as String);

  Future<void> addMembers(String conversationId, List<String> members) => _guard(() async {
        await supa.rpc('chat_add_members', params: {'p_conversation': conversationId, 'p_members': members});
      });

  Future<void> leave(String conversationId) =>
      _guard(() async => supa.rpc('chat_leave', params: {'p_conversation': conversationId}));

  Future<void> markRead(String conversationId) async {
    try {
      await supa.rpc('chat_mark_read', params: {'p_conversation': conversationId});
    } catch (_) {/* غير حرج */}
  }

  static const _select = '*, chat_attachments(*), chat_mentions(user_id)';

  /// أحدث [pageSize] رسالة (أو الأقدم من [before]) بترتيب تصاعدي.
  Future<List<ChatMessage>> messages(String conversationId, {DateTime? before}) => _guard(() async {
        var q = supa.from('chat_messages').select(_select).eq('conversation_id', conversationId);
        if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
        final rows = await q.order('created_at', ascending: false).limit(pageSize);
        return rows.map((r) => ChatMessage.fromRow(Map<String, dynamic>.from(r))).toList().reversed.toList();
      });

  Future<ChatMessage?> messageById(String id) => _guard(() async {
        final row = await supa.from('chat_messages').select(_select).eq('id', id).maybeSingle();
        return row == null ? null : ChatMessage.fromRow(Map<String, dynamic>.from(row));
      });

  /// يرفع المرفق (إن لم يكن مرفوعًا) ثم يستدعي chat_send. آمن لإعادة المحاولة بنفس المعرّفات.
  Future<void> send({
    required String conversationId,
    required String messageId,
    String? body,
    PendingAttachment? attachment,
    List<String> mentions = const [],
  }) =>
      _guard(() async {
        Map<String, dynamic>? att;
        if (attachment != null) {
          try {
            await supa.storage.from(bucket).uploadBinary(
                  attachment.storagePath,
                  attachment.bytes,
                  fileOptions: FileOptions(contentType: attachment.mimeType, upsert: false),
                );
          } on StorageException catch (e) {
            // رفع سابق لنفس الملف (إعادة محاولة): نكمل بدل أن نفشل.
            final dup = e.statusCode == '409' || e.message.toLowerCase().contains('already exists');
            if (!dup) rethrow;
          }
          att = {
            'id': attachment.id,
            'path': attachment.storagePath,
            'file_name': attachment.fileName,
            'duration_ms': attachment.durationMs,
          };
        }
        await supa.rpc('chat_send', params: {
          'p_conversation': conversationId,
          'p_message_id': messageId,
          'p_body': body,
          'p_attachment': att,
          'p_mentions': mentions,
        });
      });

  /// تنظيف أفضل جهد لملف رُفع ولم تُنشأ له رسالة (الخادم يسمح للرافع بحذفه).
  Future<void> discardUpload(PendingAttachment a) async {
    try {
      await supa.storage.from(bucket).remove([a.storagePath]);
    } catch (_) {}
  }

  /// رابط موقّع قصير العمر للمرفق (الـ bucket خاص؛ لا روابط عامة).
  Future<String> signedUrl(String path) async {
    final c = _urlCache[path];
    if (c != null && c.expires.isAfter(DateTime.now().add(const Duration(minutes: 2)))) return c.url;
    final url = await _guard(() => supa.storage.from(bucket).createSignedUrl(path, 3600));
    _urlCache[path] = (url: url, expires: DateTime.now().add(const Duration(minutes: 58)));
    return url;
  }

  void clearCache() => _urlCache.clear();
}
