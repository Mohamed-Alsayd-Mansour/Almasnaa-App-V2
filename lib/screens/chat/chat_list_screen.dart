import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../core/app_theme.dart';
import '../../models/chat.dart';
import '../../providers/chat_provider.dart';
import '../../utils/date_formatter.dart';
import '../../widgets/common_widgets.dart';
import 'conversation_screen.dart';

/// زر المحادثات في شريط التطبيق مع عدّاد غير المقروء.
class ChatButton extends StatelessWidget {
  const ChatButton({super.key});

  @override
  Widget build(BuildContext context) {
    final n = context.watch<ChatProvider>().totalUnread;
    return IconButton(
      tooltip: 'المحادثات',
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text('${n > 99 ? '99+' : n}'),
        child: const Icon(Icons.chat_bubble_outline),
      ),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChatListScreen())),
    );
  }
}

void openConversation(BuildContext context, String id, {String? focusMessageId}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ConversationScreen(conversationId: id, focusMessageId: focusMessageId),
  ));
}

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ChatProvider>().load());
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final me = context.watch<AuthController>().user!;
    final items = [...chat.conversations]..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return Scaffold(
      appBar: AppBar(title: const Text('المحادثات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newChat(context),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('محادثة جديدة'),
      ),
      body: Column(children: [
        if (chat.errorMessage != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(chat.errorMessage!, style: TextStyle(color: Colors.red.shade700))),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('لا توجد محادثات بعد. ابدأ محادثة جديدة.'))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = items[i];
                    final unread = chat.unread[c.id] ?? 0;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                        child: Icon(c.isGroup ? Icons.groups_outlined : Icons.person_outline, color: AppColors.primary),
                      ),
                      title: Text(chat.titleOf(c, me.id), style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600)),
                      subtitle: Text(c.lastMessageAt == null ? 'لا رسائل' : AppDateFormatter.dateTime(c.lastMessageAt!)),
                      trailing: unread > 0
                          ? Badge(label: Text('$unread'), backgroundColor: AppColors.accent, textColor: Colors.black)
                          : null,
                      onTap: () => openConversation(context, c.id),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Future<void> _newChat(BuildContext context) async {
    final chat = context.read<ChatProvider>();
    final me = context.read<AuthController>().user!;
    final others = chat.directory.where((u) => u.id != me.id).toList();
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('مجموعة جديدة', style: TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => Navigator.pop(ctx, 'group'),
            ),
            const Divider(height: 1),
            const Padding(padding: EdgeInsets.all(8), child: Text('أو ابدأ محادثة فردية مع:')),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final u in others)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(u.displayName),
                    subtitle: Text(u.role.label),
                    onTap: () => Navigator.pop(ctx, 'u:${u.id}'),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice.startsWith('u:')) {
      final err = await chat.openDirect(choice.substring(2), (id) => openConversation(context, id));
      if (err != null && context.mounted) showErrorSnackBar(context, err);
      return;
    }
    await _newGroup(context, others);
  }

  Future<void> _newGroup(BuildContext context, List<ChatUser> others) async {
    final titleCtl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مجموعة جديدة'),
        content: TextField(controller: titleCtl, maxLength: 80, autofocus: true, decoration: const InputDecoration(labelText: 'اسم المجموعة')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, titleCtl.text.trim()), child: const Text('التالي')),
        ],
      ),
    );
    titleCtl.dispose();
    if (title == null || title.isEmpty || !context.mounted) return;
    final picked = await showUserPicker(context, title: 'اختر الأعضاء', users: others, confirmLabel: 'إنشاء');
    if (picked == null || picked.isEmpty || !context.mounted) return;
    final err = await context.read<ChatProvider>().createGroup(title, picked.toList(), (id) => openConversation(context, id));
    if (err != null && context.mounted) showErrorSnackBar(context, err);
  }
}
