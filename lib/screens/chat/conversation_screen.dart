import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../core/app_theme.dart';
import '../../models/chat.dart';
import '../../providers/chat_provider.dart';
import '../../utils/chat_files.dart';
import '../../widgets/common_widgets.dart';
import 'message_bubble.dart';
import 'voice_recorder.dart';

/// شاشة محادثة: رسائل (نص/صوت/صورة/فيديو/ملف)، إشارات @، إرسال مرفقات وتسجيل صوتي.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversationId, this.focusMessageId});

  final String conversationId;

  /// رسالة يُنتقل إليها ويُبرز مكانها (من إشعار إشارة).
  final String? focusMessageId;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _recorder = VoiceRecorder();
  final Map<String, GlobalKey> _keys = {};
  final Map<String, String> _mentioned = {}; // الاسم المعروض -> معرّف المستخدم
  late final ChatProvider _chat;

  String? _mentionQuery;
  bool _recording = false;
  bool _busyPick = false;
  Timer? _ticker;
  String? _highlight;

  @override
  void initState() {
    super.initState();
    _chat = context.read<ChatProvider>();
    _text.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _chat.open(widget.conversationId);
      final f = widget.focusMessageId;
      if (f != null) {
        final ok = await _chat.ensureMessageLoaded(widget.conversationId, f);
        if (!mounted) return;
        if (!ok) {
          showErrorSnackBar(context, 'تعذر العثور على الرسالة المشار إليها.');
          return;
        }
        setState(() => _highlight = f);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _keys[f]?.currentContext;
          if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.4, duration: const Duration(milliseconds: 300));
        });
      }
    });
  }

  @override
  void dispose() {
    _chat.close(widget.conversationId);
    _ticker?.cancel();
    _text.dispose();
    _focus.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------- mentions

  void _onTextChanged() {
    final sel = _text.selection;
    final cursor = sel.isValid ? sel.baseOffset : _text.text.length;
    final before = _text.text.substring(0, cursor.clamp(0, _text.text.length));
    final at = before.lastIndexOf('@');
    String? q;
    if (at >= 0 && (at == 0 || RegExp(r'\s').hasMatch(before[at - 1]))) {
      final frag = before.substring(at + 1);
      if (frag.length <= 30 && !frag.contains('\n')) q = frag;
    }
    if (q != _mentionQuery) setState(() => _mentionQuery = q);
    setState(() {}); // يبدّل زر الإرسال/الميكروفون
  }

  List<ChatUser> _suggestions(String myId) {
    final q = _mentionQuery;
    if (q == null) return const [];
    final qq = q.trim().toLowerCase();
    return _chat.directory
        .where((u) => u.id != myId && (qq.isEmpty || u.displayName.toLowerCase().contains(qq)))
        .take(6)
        .toList();
  }

  void _pickMention(ChatUser u) {
    final sel = _text.selection;
    final cursor = sel.isValid ? sel.baseOffset : _text.text.length;
    final text = _text.text;
    final at = text.substring(0, cursor).lastIndexOf('@');
    if (at < 0) return;
    final insert = '@${u.displayName} ';
    final next = text.replaceRange(at, cursor, insert);
    _mentioned[u.displayName] = u.id;
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: at + insert.length));
    setState(() => _mentionQuery = null);
    _focus.requestFocus();
  }

  /// معرّفات من بقيت إشارتهم فعلًا في النص النهائي (لو حُذفت «@الاسم» لا يُشعَر صاحبها).
  List<String> _mentionIdsIn(String text) => [
        for (final e in _mentioned.entries)
          if (text.contains('@${e.key}')) e.value,
      ];

  // ------------------------------------------------------------- sending

  Future<void> _sendText() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    final ids = _mentionIdsIn(body);
    _text.clear();
    _mentioned.clear();
    setState(() => _mentionQuery = null);
    await _chat.send(widget.conversationId, body: body, mentions: ids);
  }

  Future<void> _pickFile() async {
    if (_busyPick) return;
    setState(() => _busyPick = true);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ChatFiles.allowedExtensions,
        withData: true,
      );
      if (res == null || res.files.isEmpty || !mounted) return;
      final f = res.files.first;
      final bytes = f.bytes;
      if (bytes == null) {
        showErrorSnackBar(context, 'تعذر قراءة الملف.');
        return;
      }
      final err = ChatFiles.validate(f.name, bytes.length);
      if (err != null) {
        showErrorSnackBar(context, err);
        return;
      }
      final mime = ChatFiles.mimeForName(f.name)!;
      final kind = ChatFiles.kindForMime(mime);
      final mid = _chat.newMessageId();
      final att = _chat.newAttachment(
        conversationId: widget.conversationId,
        messageId: mid,
        bytes: bytes,
        fileName: f.name,
        mimeType: mime,
        kind: kind,
      );
      final caption = _text.text.trim();
      final ids = _mentionIdsIn(caption);
      _text.clear();
      _mentioned.clear();
      await _chat.send(widget.conversationId, body: caption.isEmpty ? null : caption, attachment: att, mentions: ids);
    } catch (_) {
      if (mounted) showErrorSnackBar(context, 'تعذر اختيار الملف.');
    } finally {
      if (mounted) setState(() => _busyPick = false);
    }
  }

  // --------------------------------------------------------------- voice

  Future<void> _startRecording() async {
    try {
      final ok = await _recorder.start();
      if (!ok) {
        if (mounted) showErrorSnackBar(context, 'لا توجد صلاحية للميكروفون. فعّلها من إعدادات الجهاز.');
        return;
      }
      setState(() => _recording = true);
      _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) return;
        if (_recorder.elapsed.inMilliseconds >= VoiceRecorder.maxMs) {
          _finishRecording();
        } else {
          setState(() {});
        }
      });
    } catch (_) {
      if (mounted) showErrorSnackBar(context, 'تعذر بدء التسجيل على هذا الجهاز.');
    }
  }

  Future<void> _finishRecording({bool cancel = false}) async {
    _ticker?.cancel();
    final clip = await _recorder.stop(cancel: cancel);
    if (!mounted) return;
    setState(() => _recording = false);
    if (clip == null) {
      if (!cancel) showErrorSnackBar(context, 'التسجيل قصير جدًا.');
      return;
    }
    final err = ChatFiles.validate('x.${clip.extension}', clip.bytes.length);
    if (err != null) {
      showErrorSnackBar(context, err);
      return;
    }
    final mid = _chat.newMessageId();
    final att = _chat.newAttachment(
      conversationId: widget.conversationId,
      messageId: mid,
      bytes: clip.bytes,
      fileName: 'تسجيل-صوتي.${clip.extension}',
      mimeType: clip.mimeType,
      kind: MsgKind.audio,
      durationMs: clip.durationMs,
    );
    await _chat.send(widget.conversationId, attachment: att);
  }

  // ----------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final chat = context.watch<ChatProvider>();
    final me = auth.user!;
    final conv = chat.conversation(widget.conversationId);
    final msgs = chat.messagesOf(widget.conversationId, me.id, me.displayName);
    final sugg = _suggestions(me.id);
    final canSend = conv != null && conv.activeMembers.any((m) => m.userId == me.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(conv == null ? 'محادثة' : chat.titleOf(conv, me.id)),
        actions: [
          if (conv != null && conv.isGroup)
            IconButton(
              tooltip: 'معلومات المجموعة',
              icon: const Icon(Icons.group_outlined),
              onPressed: () => _showGroupInfo(conv),
            ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: Column(children: [
        Expanded(
          child: msgs.isEmpty
              ? const Center(child: Text('لا توجد رسائل بعد. ابدأ المحادثة.'))
              : SingleChildScrollView(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    if (chat.hasOlder(widget.conversationId))
                      TextButton(onPressed: () => chat.loadOlder(widget.conversationId), child: const Text('تحميل رسائل أقدم')),
                    for (final m in msgs)
                      KeyedSubtree(
                        key: _keys.putIfAbsent(m.id, () => GlobalKey()),
                        child: MessageBubble(
                          message: m,
                          mine: m.senderId == me.id,
                          highlighted: m.id == _highlight,
                          repository: chat.repository,
                          nameOf: (id) => chat.nameOf(id, fallback: ''),
                          onRetry: () => chat.retry(widget.conversationId, m.id),
                          onDiscard: () => chat.discard(widget.conversationId, m.id),
                        ),
                      ),
                  ]),
                ),
        ),
        if (sugg.isNotEmpty)
          Material(
            elevation: 3,
            color: Colors.white,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final u in sugg)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.alternate_email, size: 18),
                  title: Text(u.displayName),
                  subtitle: Text(u.role.label),
                  trailing: conv != null && conv.activeMembers.any((m) => m.userId == u.id)
                      ? null
                      : const Text('ليس في المحادثة', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  onTap: () => _pickMention(u),
                ),
            ]),
          ),
        if (!canSend && conv != null)
          const Padding(padding: EdgeInsets.all(12), child: Text('لم تعد عضوًا في هذه المحادثة.'))
        else
          _composer(),
      ]),
    );
  }

  Widget _composer() {
    if (_recording) {
      final e = _recorder.elapsed;
      final label = '${e.inMinutes.toString().padLeft(2, '0')}:${(e.inSeconds % 60).toString().padLeft(2, '0')}';
      return SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            IconButton(
              tooltip: 'إلغاء',
              icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
              onPressed: () => _finishRecording(cancel: true),
            ),
            Icon(Icons.fiber_manual_record, color: Colors.red.shade700, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text('جارٍ التسجيل… $label', style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton.filled(tooltip: 'إرسال', icon: const Icon(Icons.send), onPressed: () => _finishRecording()),
          ]),
        ),
      );
    }
    final hasText = _text.text.trim().isNotEmpty;
    return SafeArea(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(
            tooltip: 'إرفاق ملف',
            icon: _busyPick
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.attach_file),
            onPressed: _busyPick ? null : _pickFile,
          ),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              minLines: 1,
              maxLines: 5,
              maxLength: 4000,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'اكتب رسالة… (@ للإشارة)',
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          hasText
              ? IconButton.filled(tooltip: 'إرسال', icon: const Icon(Icons.send), onPressed: _sendText)
              : IconButton.filledTonal(tooltip: 'تسجيل صوتي', icon: const Icon(Icons.mic), onPressed: _startRecording),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------- group info

  void _showGroupInfo(ChatConversation conv) {
    final auth = context.read<AuthController>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<ChatProvider>.value(
        value: _chat,
        child: _GroupInfoSheet(conversationId: conv.id, myId: auth.user!.id, isAdmin: auth.realIsAdmin),
      ),
    );
  }
}

class _GroupInfoSheet extends StatelessWidget {
  const _GroupInfoSheet({required this.conversationId, required this.myId, required this.isAdmin});
  final String conversationId;
  final String myId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final conv = chat.conversation(conversationId);
    if (conv == null) return const SizedBox(height: 120, child: Center(child: Text('المحادثة غير متاحة')));
    final canAdd = conv.createdBy == myId || isAdmin;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(conv.title ?? 'مجموعة', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            subtitle: Text('${conv.activeMembers.length} عضو'),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final m in conv.activeMembers)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline),
                  title: Text(chat.nameOf(m.userId)),
                  trailing: m.userId == conv.createdBy ? const Text('المنشئ', style: TextStyle(fontSize: 12)) : null,
                ),
            ]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              if (canAdd)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('إضافة أعضاء'),
                    onPressed: () => _addMembers(context, chat, conv),
                  ),
                ),
              if (canAdd) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                  icon: const Icon(Icons.logout),
                  label: const Text('مغادرة'),
                  onPressed: () async {
                    final ok = await confirmDelete(context, title: 'مغادرة المجموعة', message: 'لن ترى رسائل المجموعة بعد المغادرة. هل تريد المتابعة؟');
                    if (!ok || !context.mounted) return;
                    final err = await chat.leave(conv.id);
                    if (!context.mounted) return;
                    if (err != null) {
                      showErrorSnackBar(context, err);
                    } else {
                      Navigator.of(context).pop(); // الورقة
                      Navigator.of(context).pop(); // الشاشة
                    }
                  },
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _addMembers(BuildContext context, ChatProvider chat, ChatConversation conv) async {
    final existing = conv.activeMembers.map((m) => m.userId).toSet();
    final candidates = chat.directory.where((u) => !existing.contains(u.id)).toList();
    if (candidates.isEmpty) {
      showErrorSnackBar(context, 'لا يوجد مستخدمون آخرون لإضافتهم.');
      return;
    }
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _UserPickerDialog(title: 'إضافة أعضاء', users: candidates, confirmLabel: 'إضافة'),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    final err = await chat.addMembers(conv.id, picked.toList());
    if (context.mounted && err != null) showErrorSnackBar(context, err);
  }
}

/// حوار اختيار عدة مستخدمين (للمجموعات).
class _UserPickerDialog extends StatefulWidget {
  const _UserPickerDialog({required this.title, required this.users, required this.confirmLabel});
  final String title;
  final List<ChatUser> users;
  final String confirmLabel;

  @override
  State<_UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends State<_UserPickerDialog> {
  final Set<String> _sel = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: ListView(shrinkWrap: true, children: [
          for (final u in widget.users)
            CheckboxListTile(
              dense: true,
              value: _sel.contains(u.id),
              title: Text(u.displayName),
              subtitle: Text(u.role.label),
              onChanged: (v) => setState(() => v == true ? _sel.add(u.id) : _sel.remove(u.id)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, _sel), child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// يُستخدم من قائمة المحادثات لاختيار أعضاء مجموعة جديدة.
Future<Set<String>?> showUserPicker(BuildContext context,
        {required String title, required List<ChatUser> users, required String confirmLabel}) =>
    showDialog<Set<String>>(
      context: context,
      builder: (_) => _UserPickerDialog(title: title, users: users, confirmLabel: confirmLabel),
    );
