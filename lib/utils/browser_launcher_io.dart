import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

/// يحفظ تقرير HTML في مجلد مؤقت ثم يفتحه في المتصفح الافتراضي.
///
/// - أندرويد / iOS: يُفتح الملف عبر FileProvider (open_filex) لأن روابط
///   file:// محظورة على أندرويد الحديث.
/// - ويندوز / ماك / لينكس: يُفتح بالتطبيق الافتراضي لملفات HTML.
Future<void> openHtmlInBrowser({required String html, required String fileName}) async {
  final dir = await _reportsDirectory();
  // اسم ملف مميز بحروف إنجليزية فقط (الطابع الزمني) داخل مجلد ثابت واحد.
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final file = File('${dir.path}${Platform.pathSeparator}almasnaa-report-$stamp.html');
  await file.writeAsString(html, encoding: utf8, flush: true);
  _cleanOldReports(dir);
  final path = file.path;

  if (Platform.isAndroid || Platform.isIOS) {
    final result = await OpenFilex.open(path, type: 'text/html');
    if (result.type != ResultType.done) {
      throw StateError(
        result.type == ResultType.noAppToOpen
            ? 'لا يوجد متصفح لفتح ملف HTML على هذا الجهاز.'
            : 'تعذر فتح التقرير: ${result.message}',
      );
    }
    return;
  }

  ProcessResult? result;
  if (Platform.isWindows) {
    result = await Process.run('rundll32', ['url.dll,FileProtocolHandler', path]);
  } else if (Platform.isMacOS) {
    result = await Process.run('open', [path]);
  } else if (Platform.isLinux) {
    result = await Process.run('xdg-open', [path]);
  }
  if (result != null && result.exitCode == 0) return;

  // محاولة أخيرة عبر url_launcher.
  if (!await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication)) {
    throw StateError('تعذر فتح ملف HTML في المتصفح.');
  }
}

/// مجلد ثابت واحد لكل التقارير بدل مجلد عشوائي جديد في كل مرة:
/// - ويندوز: %LOCALAPPDATA%\\Almasnaa\\Reports
/// - بقية المنصات: Almasnaa/Reports داخل المجلد المؤقت الخاص بالتطبيق.
Future<Directory> _reportsDirectory() async {
  final sep = Platform.pathSeparator;
  String base;
  final localAppData = Platform.isWindows ? Platform.environment['LOCALAPPDATA'] : null;
  if (localAppData != null && localAppData.isNotEmpty) {
    base = localAppData;
  } else {
    base = Directory.systemTemp.path;
  }
  final dir = Directory('$base${sep}Almasnaa${sep}Reports');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// حذف التقارير الأقدم من 7 أيام حتى لا يتضخم المجلد (بصمت عند أي خطأ).
Future<void> _cleanOldReports(Directory dir) async {
  try {
    final limit = DateTime.now().subtract(const Duration(days: 7));
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.html') && (await e.lastModified()).isBefore(limit)) {
        await e.delete();
      }
    }
  } catch (_) {}
}
