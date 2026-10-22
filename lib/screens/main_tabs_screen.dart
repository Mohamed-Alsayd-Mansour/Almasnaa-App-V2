import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../providers/daily_provider.dart';
import '../providers/people_provider.dart';
import '../providers/records_provider.dart';
import '../providers/rooms_provider.dart';
import '../services/live_sync_service.dart';

import 'admin/admin_screen.dart';
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
    with SingleTickerProviderStateMixin {
  /// التبويبات حسب الدور (العرض فقط؛ الحماية الفعلية في الخادم):
  /// الأدمن: الكل + الأدمن | الرصيص والمشرف: الغرف، اليومية، السجل، الإعدادات.
  late final List<_TabEntry> _entries;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final isAdmin = context.read<AuthController>().isAdmin;
    _entries = [
      const _TabEntry(Icons.meeting_room_outlined, 'الغرف', RoomsScreen()),
      const _TabEntry(Icons.event_note_outlined, 'اليومية', DailyScreen()),
      const _TabEntry(Icons.fact_check_outlined, 'السجل', RecordsScreen()),
      const _TabEntry(Icons.settings_outlined, 'الإعدادات', SettingsScreen()),
      if (isAdmin && showResearchTab)
        const _TabEntry(Icons.query_stats_outlined, 'الاستعلامات', ResearchScreen()),
      if (isAdmin)
        const _TabEntry(Icons.admin_panel_settings_outlined, 'الأدمن', AdminScreen()),
    ];
    _tabController = TabController(length: _entries.length, vsync: this);
    // المزامنة اللحظية: إعادة تحميل الشاشات بعد وصول بيانات من السحابة.
    LiveSyncService.instance.onRemoteApplied = () async {
      if (!mounted) return;
      await Future.wait([
        context.read<RoomsProvider>().loadRooms(),
        context.read<DailyProvider>().load(),
        context.read<RecordsProvider>().load(),
        context.read<PeopleProvider>().load(),
      ]);
    };
  }

  @override
  void dispose() {
    LiveSyncService.instance.onRemoteApplied = null;
    _tabController.dispose();
    super.dispose();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('المصنع'),
        actions: const [_UserMenu()],
        bottom: TabBar(
          controller: _tabController,
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
      body: TabBarView(
        controller: _tabController,
        children: [for (final e in _entries) e.screen],
      ),
    );
  }
}

class _TabEntry {
  const _TabEntry(this.icon, this.label, this.screen);
  final IconData icon;
  final String label;
  final Widget screen;
}

/// اسم المستخدم ودوره + تسجيل الخروج.
class _UserMenu extends StatelessWidget {
  const _UserMenu();

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
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            '${u.displayName} • ${u.role.label}'
            '${auth.isRassas && auth.currentSupervisorName != null ? '\nالمشرف: ${auth.currentSupervisorName}' : ''}',
          ),
        ),
        const PopupMenuItem<String>(value: 'out', child: Text('تسجيل الخروج')),
      ],
    );
  }
}
