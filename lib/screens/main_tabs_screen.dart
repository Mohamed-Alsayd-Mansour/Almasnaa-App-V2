import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/app_user.dart';
import '../auth/auth_controller.dart';
import '../core/app_theme.dart';
import '../providers/chat_provider.dart';
import '../providers/daily_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/people_provider.dart';
import '../repositories/daily_entry_repository.dart';
import '../services/app_navigator.dart';
import '../widgets/common_widgets.dart';
import '../widgets/notifications_button.dart';
import '../providers/records_provider.dart';
import '../providers/rooms_provider.dart';
import '../services/realtime_hub.dart';
import '../widgets/sync_indicator.dart';

import 'admin/admin_screen.dart';
import 'chat/chat_list_screen.dart';
import 'daily/daily_screen.dart';
import 'records/records_screen.dart';
import 'research/research_screen.dart';
import 'rooms/rooms_screen.dart';
import 'settings/settings_screen.dart';
import '../utils/platform_utils.dart';

/// نقطة الدخول لواجهة التطبيق: تبويبات الغرف / اليومية / السجل / الإعدادات / الاستعلامات.
class MainTabsScreen extends StatefulWidget {
  const MainTabsScreen({super.key});

  @override
  State<MainTabsScreen> createState() => _MainTabsScreenState();
}

class _MainTabsScreenState extends State<MainTabsScreen>
    with TickerProviderStateMixin {
  /// التبويبات حسب الدور المعروض (العرض فقط؛ الحماية الفعلية في الخادم):
  /// الأدمن: الكل + الأدمن | الرصيص والمشرف: الغرف، اليومية، السجل، الإعدادات.
  /// أثناء «عرض كمستخدم» يُحسب الدور من المستخدم المستهدف.
  List<_TabEntry> _entries = const [];
  TabController? _tabController;
  String? _viewKey;
  int _recordsIndex = 2;

  List<_TabEntry> _buildEntries(AuthController auth) {
    final isAdmin = auth.isAdmin;
    return [
      const _TabEntry(Icons.meeting_room_outlined, 'الغرف', RoomsScreen()),
      const _TabEntry(Icons.event_note_outlined, 'اليومية', DailyScreen()),
      const _TabEntry(Icons.fact_check_outlined, 'السجل', RecordsScreen()),
      const _TabEntry(Icons.settings_outlined, 'الإعدادات', SettingsScreen()),
      if (isAdmin && showResearchTab)
        const _TabEntry(Icons.query_stats_outlined, 'الاستعلامات', ResearchScreen()),
      if (isAdmin)
        const _TabEntry(Icons.admin_panel_settings_outlined, 'الأدمن', AdminScreen()),
    ];
  }

  void _setupTabs(AuthController auth) {
    final old = _tabController;
    _entries = _buildEntries(auth);
    _recordsIndex = _entries.indexWhere((e) => e.label == 'السجل');
    _tabController = TabController(length: _entries.length, vsync: this);
    if (old != null) {
      // نتخلص من القديم بعد انتهاء الإطار الحالي حتى لا يستخدمه TabBar أثناء إعادة البناء.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  Future<void> _reloadAllData(AuthController auth) async {
    final daily = context.read<DailyProvider>();
    final records = context.read<RecordsProvider>();
    daily.reset();
    daily.role = auth.effectiveRole;
    records.reset();
    await Future.wait([
      context.read<RoomsProvider>().loadRooms(silent: true),
      daily.load(),
      records.load(),
      context.read<PeopleProvider>().load(),
    ]);
  }

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _viewKey = auth.viewAs?.id;
    _setupTabs(auth);
    context.read<DailyProvider>().role = auth.effectiveRole;
    // المزامنة اللحظية تلقائية دائمًا: أي تغيير من جهاز آخر يعيد تحميل البيانات بهدوء.
    RealtimeHub.instance.start(() async {
      if (!mounted) return;
      await Future.wait([
        context.read<RoomsProvider>().loadRooms(silent: true),
        context.read<DailyProvider>().load(silent: true),
        context.read<RecordsProvider>().load(silent: true),
        context.read<PeopleProvider>().load(),
        context.read<NotificationsProvider>().load(),
        context.read<ChatProvider>().load(silent: true),
      ]);
    });
    // التحميل الأولي بعد الدخول (المزودات تُفرَّغ عند الخروج).
    context.read<PeopleProvider>().load();
    context.read<NotificationsProvider>().load();
    context.read<ChatProvider>().load();
    AppNavigator.instance.addListener(_onNavRequest);
  }

  @override
  void dispose() {
    AppNavigator.instance.removeListener(_onNavRequest);
    RealtimeHub.instance.stop();
    _tabController?.dispose();
    super.dispose();
  }

  /// انتقال من إشعار: إلى السجل المرتبط (يُعرض وحده) أو إلى الرسالة المشار إليها.
  Future<void> _onNavRequest() async {
    final r = AppNavigator.instance.take();
    if (r == null || !mounted) return;
    if (r.isRecord) {
      if (_recordsIndex >= 0) _tabController?.animateTo(_recordsIndex);
      await context.read<RecordsProvider>().applyFilters(RecordSearchFilters(entryId: r.entryId));
      return;
    }
    final chat = context.read<ChatProvider>();
    await chat.load(silent: true);
    if (!mounted) return;
    if (chat.conversation(r.conversationId!) == null) {
      showErrorSnackBar(context, 'لا تملك صلاحية عرض هذه المحادثة.');
      return;
    }
    openConversation(context, r.conversationId!, focusMessageId: r.messageId);
  }

  Tab _tab(IconData icon, String label) => Tab(
        height: isMobileApp ? 58 : null,
        iconMargin: EdgeInsets.only(bottom: isMobileApp ? 3 : 10),
        icon: Icon(icon, size: isMobileApp ? 22 : null),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, softWrap: false),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (auth.viewAs?.id != _viewKey) {
      // دخول/خروج من وضع «عرض كمستخدم»: تبويبات الدور الجديد وبيانات نطاقه.
      _viewKey = auth.viewAs?.id;
      _setupTabs(auth);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reloadAllData(auth);
      });
    }
    final controller = _tabController!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('المصنع'),
        actions: const [SyncIndicator(), ChatButton(), NotificationsButton(), _UserMenu()],
        bottom: TabBar(
          controller: controller,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          // على الهاتف: عناوين أصغر وحشو أقل ليتسع النص كاملًا تحت الأيقونة.
          labelPadding: isMobileApp
              ? const EdgeInsets.symmetric(horizontal: 2)
              : null,
          labelStyle: TextStyle(
              fontWeight: FontWeight.w800, fontSize: isMobileApp ? 12.5 : null),
          unselectedLabelStyle: TextStyle(
              fontWeight: FontWeight.w800, fontSize: isMobileApp ? 12.5 : null),
          tabs: [for (final e in _entries) _tab(e.icon, e.label)],
        ),
      ),
      body: Column(children: [
        if (auth.viewAs != null) _ViewAsBanner(user: auth.viewAs!, onExit: auth.stopViewAs),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [for (final e in _entries) e.screen],
          ),
        ),
      ]),
    );
  }
}

class _TabEntry {
  const _TabEntry(this.icon, this.label, this.screen);
  final IconData icon;
  final String label;
  final Widget screen;
}

/// شريط وضع «عرض كمستخدم»: يوضح بجلاء أن العرض بنطاق مستخدم آخر وأن الصلاحيات الفعلية للأدمن.
class _ViewAsBanner extends StatelessWidget {
  const _ViewAsBanner({required this.user, required this.onExit});
  final DirectoryUser user;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          const Icon(Icons.visibility_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'وضع العرض: تشاهد التطبيق كما يراه ${user.displayName} (${user.role.label}). '
              'أي تعديل يُنفَّذ بصلاحياتك كأدمن ويُسجَّل باسمك مع ذكر هذا المستخدم.',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
          TextButton(onPressed: onExit, child: const Text('إنهاء')),
        ]),
      ),
    );
  }
}

/// اسم المستخدم ودوره + عرض كمستخدم (للأدمن) + تسجيل الخروج.
class _UserMenu extends StatelessWidget {
  const _UserMenu();

  Future<void> _pickViewAs(BuildContext context) async {
    final auth = context.read<AuthController>();
    try {
      final users = await auth.activeUsers();
      if (!context.mounted) return;
      final picked = await showDialog<DirectoryUser>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('عرض التطبيق كمستخدم'),
          children: [
            for (final u in users)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, u),
                child: Text('${u.displayName} • ${u.role.label}'),
              ),
          ],
        ),
      );
      if (picked != null) auth.startViewAs(picked);
    } catch (_) {
      if (context.mounted) showErrorSnackBar(context, 'تعذر تحميل قائمة المستخدمين.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final u = auth.user;
    if (u == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'الحساب',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (v) {
        if (v == 'out') auth.signOut();
        if (v == 'viewas') _pickViewAs(context);
        if (v == 'stopview') auth.stopViewAs();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            '${u.displayName} • ${u.role.label}'
            '${auth.isRassas && auth.viewAs == null && auth.currentSupervisorName != null ? '\nالمشرف: ${auth.currentSupervisorName}' : ''}',
          ),
        ),
        if (auth.realIsAdmin && auth.viewAs == null)
          const PopupMenuItem<String>(value: 'viewas', child: Text('عرض كمستخدم…')),
        if (auth.viewAs != null)
          const PopupMenuItem<String>(value: 'stopview', child: Text('إنهاء وضع العرض')),
        const PopupMenuItem<String>(value: 'out', child: Text('تسجيل الخروج')),
      ],
    );
  }
}
