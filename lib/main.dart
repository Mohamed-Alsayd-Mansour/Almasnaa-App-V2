import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'auth/auth_controller.dart';
import 'core/app_theme.dart';
import 'core/env.dart';
import 'providers/daily_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/people_provider.dart';
import 'providers/records_provider.dart';
import 'providers/rooms_provider.dart';
import 'screens/splash_screen.dart';
import 'services/legacy_cleanup.dart';
import 'services/realtime_hub.dart';
import 'utils/platform_utils.dart';

/// window_manager يعمل على الديسكتوب فقط
bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyMobileSystemUi();

  if (_isDesktop) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      center: true,
      title: 'المصنع',
    );

    await windowManager.waitUntilReadyToShow(
      windowOptions,
      () async {
        // مش بنفعّل Fullscreen هنا: على Windows لو اتفعّل قبل أول فريم
        // المحتوى بيفضل بحجم النافذة القديم وبيقف الـ input.
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  if (Env.isConfigured) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  }

  // 2.0: لا أسرار على الجهاز. يُحذف أي رمز GitHub قديم (بيانات 1.0 المحلية لا تُمس).
  await LegacyCleanup.wipeSecrets();
  runApp(const AlmasnaaApp());
}

class AlmasnaaApp extends StatelessWidget {
  const AlmasnaaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RoomsProvider()),
        ChangeNotifierProvider(create: (_) => DailyProvider()),
        ChangeNotifierProvider(create: (_) => RecordsProvider()),
        ChangeNotifierProvider(create: (_) => PeopleProvider()),
        ChangeNotifierProvider(create: (_) => NotificationsProvider()),
        // آخر المزودات: سياقه يرى كل ما قبله، فيفرّغ بياناتها عند انتهاء الجلسة.
        ChangeNotifierProvider(
          create: (ctx) => AuthController(onSessionEnded: () {
            RealtimeHub.instance.stop();
            ctx.read<RoomsProvider>().reset();
            ctx.read<PeopleProvider>().reset();
            ctx.read<DailyProvider>().reset();
            ctx.read<RecordsProvider>().reset();
            ctx.read<NotificationsProvider>().reset();
          })
            ..init(),
        ),
      ],
      child: const _FullscreenKeys(child: _App()),
    );
  }
}

/// اختصارات الكيبورد:
///  - Esc : الخروج من ملء الشاشة (لو مفعّل)
///  - F11 : تبديل ملء الشاشة
///
/// بنستخدم HardwareKeyboard مباشرة عشان يشتغل مهما كان الفوكس فين،
/// وبنرجّع false عشان الـ Esc يفضل شغال عادي في الدايالوجات.
class _FullscreenKeys extends StatefulWidget {
  const _FullscreenKeys({required this.child});

  final Widget child;

  @override
  State<_FullscreenKeys> createState() => _FullscreenKeysState();
}

class _FullscreenKeysState extends State<_FullscreenKeys>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);

    // نفعّل Fullscreen بعد ما أول فريم يترسم ويستقر
    if (_isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) await _setFullscreen(true);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) applyMobileSystemUi();
  }

  bool _onKey(KeyEvent event) {
    if (!_isDesktop || event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_setFullscreen(false, onlyIfFullscreen: true));
    } else if (event.logicalKey == LogicalKeyboardKey.f11) {
      unawaited(_toggleFullscreen());
    }
    return false;
  }

  Future<void> _setFullscreen(bool value, {bool onlyIfFullscreen = false}) async {
    try {
      if (onlyIfFullscreen && !await windowManager.isFullScreen()) return;
      await windowManager.setFullScreen(value);
    } catch (_) {
      // تجاهل أي خطأ في تغيير حالة النافذة
    }
  }

  Future<void> _toggleFullscreen() async {
    try {
      final isFull = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!isFull);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'المصنع',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(),
    );
  }
}