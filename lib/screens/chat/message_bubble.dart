import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../models/chat.dart';
import '../../repositories/chat_repository.dart';
import '../../utils/chat_files.dart';
import '../../utils/date_formatter.dart';

/// فقاعة رسالة: نص (مع إبراز الإشارات) و/أو مرفق، وحالة الإرسال للرسائل المحلية.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.repository,
    required this.nameOf,
    this.highlighted = false,
    this.onRetry,
    this.onDiscard,
  });

  final ChatMessage message;
  final bool mine;
  final bool highlighted;
  final ChatRepository repository;
  final String Function(String userId) nameOf;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final bg = highlighted
        ? Colors.amber.withValues(alpha: 0.35)
        : mine
            ? AppColors.primary.withValues(alpha: 0.12)
            : Colors.white;
    final failed = message.state == SendState.failed;
    return Align(
      alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82 > 520 ? 520 : MediaQuery.of(context).size.width * 0.82),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: failed ? Colors.red.shade300 : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(message.senderName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.primary)),
                ),
              for (final a in message.attachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _AttachmentView(
                    attachment: a,
                    kind: message.kind,
                    repository: repository,
                    uploaded: message.state == SendState.sent,
                  ),
                ),
              if ((message.body ?? '').trim().isNotEmpty)
                SelectableText.rich(_withMentions(context, message.body!, message.mentionIds.map(nameOf).toList())),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(AppDateFormatter.dateTime(message.createdAt),
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                if (mine) ...[
                  const SizedBox(width: 6),
                  switch (message.state) {
                    SendState.sending => const SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.6)),
                    SendState.failed => Icon(Icons.error_outline, size: 14, color: Colors.red.shade700),
                    SendState.sent => const Icon(Icons.done, size: 14, color: AppColors.textSecondary),
                  },
                ],
              ]),
              if (failed)
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                  Text(message.error ?? 'تعذر الإرسال', style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                  TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
                  TextButton(onPressed: onDiscard, child: const Text('حذف')),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  /// يبرز «@الاسم» لكل مستخدم تمت الإشارة إليه في هذه الرسالة (المطابقة بالمعرّفات المخزنة،
  /// والاسم المعروض يؤخذ من الدليل الحالي).
  TextSpan _withMentions(BuildContext context, String text, List<String> names) {
    const base = TextStyle(fontSize: 14.5, height: 1.35, color: AppColors.textPrimary);
    final clean = names.where((n) => n.isNotEmpty).toSet().toList()..sort((a, b) => b.length.compareTo(a.length));
    if (clean.isEmpty) return TextSpan(text: text, style: base);
    final re = RegExp('@(${clean.map(RegExp.escape).join('|')})');
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(
        text: m.group(0),
        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, backgroundColor: AppColors.primary.withValues(alpha: 0.10)),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: base, children: spans);
  }
}

class _AttachmentView extends StatelessWidget {
  const _AttachmentView({required this.attachment, required this.kind, required this.repository, required this.uploaded});

  final ChatAttachment attachment;
  final MsgKind kind;
  final ChatRepository repository;
  final bool uploaded;

  @override
  Widget build(BuildContext context) {
    // قبل اكتمال الرفع لا يوجد رابط موقّع بعد: نعرض بطاقة بسيطة.
    if (!uploaded) return _FileTile(attachment: attachment, kind: kind, repository: null);
    switch (kind) {
      case MsgKind.image:
        return _ImageAttachment(attachment: attachment, repository: repository);
      case MsgKind.audio:
        return _AudioAttachment(attachment: attachment, repository: repository);
      default:
        return _FileTile(attachment: attachment, kind: kind, repository: repository);
    }
  }
}

Future<void> _openExternally(BuildContext context, ChatRepository repo, String path) async {
  try {
    final url = await repo.signedUrl(path);
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الملف على هذا الجهاز.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ChatException ? e.message : 'تعذر فتح الملف.')));
    }
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.attachment, required this.kind, required this.repository});
  final ChatAttachment attachment;
  final MsgKind kind;
  final ChatRepository? repository;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      MsgKind.video => Icons.videocam_outlined,
      MsgKind.image => Icons.image_outlined,
      MsgKind.audio => Icons.mic_none,
      _ => attachment.mimeType == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.description_outlined,
    };
    return InkWell(
      onTap: repository == null ? null : () => _openExternally(context, repository!, attachment.path),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(attachment.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                repository == null
                    ? 'جارٍ الرفع… ${ChatFiles.sizeLabel(attachment.sizeBytes)}'
                    : '${ChatFiles.sizeLabel(attachment.sizeBytes)} • اضغط للفتح',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ImageAttachment extends StatefulWidget {
  const _ImageAttachment({required this.attachment, required this.repository});
  final ChatAttachment attachment;
  final ChatRepository repository;

  @override
  State<_ImageAttachment> createState() => _ImageAttachmentState();
}

class _ImageAttachmentState extends State<_ImageAttachment> {
  late final Future<String> _url = widget.repository.signedUrl(widget.attachment.path);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.hasError) return _FileTile(attachment: widget.attachment, kind: MsgKind.image, repository: widget.repository);
        if (!snap.hasData) {
          return const SizedBox(height: 120, width: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final url = snap.data!;
        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(12),
              child: Stack(children: [
                InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ),
              ]),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _FileTile(attachment: widget.attachment, kind: MsgKind.image, repository: widget.repository),
              loadingBuilder: (c, child, p) => p == null ? child : const SizedBox(height: 120, width: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          ),
        );
      },
    );
  }
}

class _AudioAttachment extends StatefulWidget {
  const _AudioAttachment({required this.attachment, required this.repository});
  final ChatAttachment attachment;
  final ChatRepository repository;

  @override
  State<_AudioAttachment> createState() => _AudioAttachmentState();
}

class _AudioAttachmentState extends State<_AudioAttachment> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  Duration? _dur;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.durationMs != null) _dur = Duration(milliseconds: widget.attachment.durationMs!);
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _dur = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _pos = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    try {
      if (_state == PlayerState.playing) {
        await _player.pause();
        return;
      }
      if (_state == PlayerState.paused) {
        await _player.resume();
        return;
      }
      setState(() {
        _loading = true;
        _error = null;
      });
      final url = await widget.repository.signedUrl(widget.attachment.path);
      await _player.play(UrlSource(url));
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تشغيل الصوت');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = (_dur ?? Duration.zero).inMilliseconds;
    final value = total <= 0 ? 0.0 : (_pos.inMilliseconds / total).clamp(0.0, 1.0);
    return SizedBox(
      width: 230,
      child: Row(children: [
        _loading
            ? const SizedBox(width: 40, height: 40, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
                icon: Icon(_state == PlayerState.playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 32, color: AppColors.primary),
                onPressed: _toggle,
              ),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: value, minHeight: 4),
            const SizedBox(height: 4),
            Text(
              _error ?? ChatFiles.durationLabel(_state == PlayerState.stopped ? total : _pos.inMilliseconds),
              style: TextStyle(fontSize: 11, color: _error == null ? AppColors.textSecondary : Colors.red.shade700),
            ),
          ]),
        ),
      ]),
    );
  }
}
