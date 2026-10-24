import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/supa.dart';
import '../models/chat.dart';
import '../repositories/chat_repository.dart';

/// حالة المحادثات: القائمة وغير المقروء والرسائل المفتوحة وصندوق الإرسال المحلي.
/// الخادم هو المصدر؛ المزامنة اللحظية (RealtimeHub) تستدعي [load] عند أي تغيير.
class ChatProvider extends ChangeNotifier {
  ChatProvider({ChatRepository? repository}) : _repo = repository ?? ChatRepository();

  final ChatRepository _repo;
  static const _uuid = Uuid();

  List<ChatUser> directory = [];
  List<ChatConversation> conversations = [];
  Map<String, int> unread = {};
  String? errorMessage;

  /// المحادثة المفتوحة حاليًا على الشاشة (لتحديث رسائلها وتعليمها مقروءة).
  String? openConversationId;

  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, bool> _hasOlder = {};
  final Map<String, List<_Outgoing>> _outbox = {};

  ChatRepository get repository => _repo;

  int get totalUnread => unread.values.fold(0, (a, b) => a + b);

  void reset() {
    directory = [];
    conversations = [];
    unread = {};
    errorMessage = null;
    openConversationId = null;
    _messages.clear();
    _hasOlder.clear();
    _outbox.clear();
    _repo.clearCache();
    notifyListeners();
  }

  // ------------------------------------------------------------------ lookup

  String nameOf(String userId, {String fallback = 'مستخدم'}) {
    for (final u in directory) {
      if (u.id == userId) return u.displayName;
    }
    return fallback;
  }

  ChatConversation? conversation(String id) {
    for (final c in conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// عنوان العرض: اسم المجموعة، أو اسم الطرف الآخر في المحادثة الفردية.
  String titleOf(ChatConversation c, String myId) {
    if (c.isGroup) return c.title ?? 'مجموعة';
    final other = c.activeMembers.where((m) => m.userId != myId).toList();
    return other.isEmpty ? 'محادثة' : nameOf(other.first.userId);
  }

  bool hasOlder(String conversationId) => _hasOlder[conversationId] ?? false;

  /// رسائل المحادثة: ما وصل الخادم + الرسائل قيد الإرسال/الفاشلة محليًا.
  List<ChatMessage> messagesOf(String conversationId, String myId, String myName) {
    final server = _messages[conversationId] ?? const <ChatMessage>[];
    final ids = {for (final m in server) m.id};
    final local = [
      for (final o in _outbox[conversationId] ?? const <_Outgoing>[])
        if (!ids.contains(o.id)) o.toMessage(myId, myName),
    ];
    return [...server, ...local];
  }

  // -------------------------------------------------------------------- load

  Future<void> load({bool silent = false}) async {
    try {
      final results = await Future.wait([_repo.directory(), _repo.conversations(), _repo.unread()]);
      directory = results[0] as List<ChatUser>;
      conversations = results[1] as List<ChatConversation>;
      unread = results[2] as Map<String, int>;
      errorMessage = null;
      final open = openConversationId;
      if (open != null) {
        await _refreshLatest(open);
        await _repo.markRead(open);
        unread = {...unread}..remove(open);
      }
    } catch (e) {
      errorMessage = e is ChatException ? e.message : friendlyError(e);
    }
    notifyListeners();
  }

  Future<void> _refreshLatest(String id) async {
    final fresh = await _repo.messages(id);
    final old = _messages[id] ?? const <ChatMessage>[];
    // نحافظ على الرسائل الأقدم التي حمّلها المستخدم يدويًا.
    final earliest = fresh.isEmpty ? null : fresh.first.createdAt;
    final keep = earliest == null ? <ChatMessage>[] : old.where((m) => m.createdAt.isBefore(earliest)).toList();
    _messages[id] = [...keep, ...fresh];
    _hasOlder[id] = _hasOlder[id] ?? fresh.length >= ChatRepository.pageSize;
    _outbox[id]?.removeWhere((o) => o.state == SendState.sending && fresh.any((m) => m.id == o.id));
  }

  /// عند فتح شاشة محادثة.
  Future<void> open(String id) async {
    openConversationId = id;
    try {
      await _refreshLatest(id);
      await _repo.markRead(id);
      unread = {...unread}..remove(id);
    } catch (e) {
      errorMessage = e is ChatException ? e.message : friendlyError(e);
    }
    notifyListeners();
  }

  void close(String id) {
    if (openConversationId == id) openConversationId = null;
  }

  Future<void> loadOlder(String id) async {
    final cur = _messages[id] ?? const <ChatMessage>[];
    if (cur.isEmpty) return;
    try {
      final older = await _repo.messages(id, before: cur.first.createdAt);
      _messages[id] = [...older, ...cur];
      _hasOlder[id] = older.length >= ChatRepository.pageSize;
    } catch (e) {
      errorMessage = e is ChatException ? e.message : friendlyError(e);
    }
    notifyListeners();
  }

  /// يتأكد أن رسالة معيّنة محمّلة (للانتقال من إشعار إشارة). يعيد false إن لم توجد/لا صلاحية.
  Future<bool> ensureMessageLoaded(String conversationId, String messageId) async {
    try {
      if ((_messages[conversationId] ?? const []).any((m) => m.id == messageId)) return true;
      final target = await _repo.messageById(messageId);
      if (target == null || target.conversationId != conversationId) return false;
      for (var i = 0; i < 12; i++) {
        if ((_messages[conversationId] ?? const []).any((m) => m.id == messageId)) return true;
        if (!hasOlder(conversationId)) break;
        await loadOlder(conversationId);
      }
      return (_messages[conversationId] ?? const []).any((m) => m.id == messageId);
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------- conversations

  Future<String?> openDirect(String userId, void Function(String id) onReady) async {
    try {
      final id = await _repo.openDirect(userId);
      await load(silent: true);
      onReady(id);
      return null;
    } catch (e) {
      return e is ChatException ? e.message : friendlyError(e);
    }
  }

  Future<String?> createGroup(String title, List<String> members, void Function(String id) onReady) async {
    try {
      final id = await _repo.createGroup(title.trim(), members);
      await load(silent: true);
      onReady(id);
      return null;
    } catch (e) {
      return e is ChatException ? e.message : friendlyError(e);
    }
  }

  Future<String?> addMembers(String id, List<String> members) async {
    try {
      await _repo.addMembers(id, members);
      await load(silent: true);
      return null;
    } catch (e) {
      return e is ChatException ? e.message : friendlyError(e);
    }
  }

  Future<String?> leave(String id) async {
    try {
      await _repo.leave(id);
      close(id);
      _messages.remove(id);
      await load(silent: true);
      return null;
    } catch (e) {
      return e is ChatException ? e.message : friendlyError(e);
    }
  }

  // ------------------------------------------------------------------ send

  /// يرسل نصًا (مع إشارات) أو مرفقًا. المعرّفات تُنشأ هنا مرة واحدة وتُعاد كما هي عند إعادة المحاولة،
  /// لذلك لا تتكرر الرسالة ولا المرفق ولا إشعار الإشارة مهما تكرر الضغط أو انقطع الاتصال.
  Future<void> send(String conversationId,
      {String? body, PendingAttachment? attachment, List<String> mentions = const []}) async {
    final out = _Outgoing(
      id: attachment?.messageId ?? _uuid.v4(),
      conversationId: conversationId,
      body: body?.trim(),
      attachment: attachment,
      mentions: mentions,
    );
    (_outbox[conversationId] ??= []).add(out);
    notifyListeners();
    await _deliver(out);
  }

  PendingAttachment newAttachment({
    required String conversationId,
    required String messageId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required MsgKind kind,
    int? durationMs,
  }) =>
      PendingAttachment(
        id: _uuid.v4(),
        messageId: messageId,
        conversationId: conversationId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        kind: kind,
        durationMs: durationMs,
      );

  String newMessageId() => _uuid.v4();

  Future<void> _deliver(_Outgoing o) async {
    if (o.state == SendState.sending && o.inFlight) return; // ضغطة مكررة
    o.state = SendState.sending;
    o.error = null;
    o.inFlight = true;
    notifyListeners();
    try {
      await _repo.send(
        conversationId: o.conversationId,
        messageId: o.id,
        body: o.body,
        attachment: o.attachment,
        mentions: o.mentions,
      );
      final list = _messages[o.conversationId] ?? const <ChatMessage>[];
      final fresh = await _repo.messages(o.conversationId);
      final earliest = fresh.isEmpty ? null : fresh.first.createdAt;
      _messages[o.conversationId] = [
        ...earliest == null ? <ChatMessage>[] : list.where((m) => m.createdAt.isBefore(earliest)),
        ...fresh,
      ];
      _outbox[o.conversationId]?.removeWhere((x) => x.id == o.id);
      if (openConversationId == o.conversationId) await _repo.markRead(o.conversationId);
    } catch (e) {
      o.state = SendState.failed;
      o.error = e is ChatException ? e.message : friendlyError(e);
    } finally {
      o.inFlight = false;
    }
    notifyListeners();
  }

  /// إعادة إرسال رسالة فاشلة بنفس المعرّفات.
  Future<void> retry(String conversationId, String messageId) async {
    final o = _find(conversationId, messageId);
    if (o != null) await _deliver(o);
  }

  Future<void> discard(String conversationId, String messageId) async {
    final o = _find(conversationId, messageId);
    if (o == null) return;
    _outbox[conversationId]?.remove(o);
    if (o.attachment != null) await _repo.discardUpload(o.attachment!);
    notifyListeners();
  }

  _Outgoing? _find(String conversationId, String messageId) {
    for (final o in _outbox[conversationId] ?? const <_Outgoing>[]) {
      if (o.id == messageId) return o;
    }
    return null;
  }
}

class _Outgoing {
  _Outgoing({
    required this.id,
    required this.conversationId,
    required this.body,
    required this.attachment,
    required this.mentions,
  }) : createdAt = DateTime.now();

  final String id;
  final String conversationId;
  final String? body;
  final PendingAttachment? attachment;
  final List<String> mentions;
  final DateTime createdAt;
  SendState state = SendState.sending;
  String? error;
  bool inFlight = false;

  ChatMessage toMessage(String myId, String myName) => ChatMessage(
        id: id,
        conversationId: conversationId,
        senderId: myId,
        senderName: myName,
        kind: attachment?.kind ?? MsgKind.text,
        body: body,
        createdAt: createdAt,
        attachments: attachment == null
            ? const []
            : [
                ChatAttachment(
                  id: attachment!.id,
                  path: attachment!.storagePath,
                  fileName: attachment!.fileName,
                  mimeType: attachment!.mimeType,
                  sizeBytes: attachment!.bytes.length,
                  durationMs: attachment!.durationMs,
                ),
              ],
        mentionIds: mentions,
        state: state,
        error: error,
      );
}
