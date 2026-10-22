import 'dart:async';
import 'dart:convert';
import 'dart:html' as web;

/// يفتح التقرير في تبويب جديد؛ وإن منع المتصفح النافذة المنبثقة يُنزَّل الملف.
Future<void> openHtmlInBrowser({required String html, required String fileName}) async {
  final blob = web.Blob(<dynamic>[utf8.encode(html)], 'text/html;charset=utf-8');
  final url = web.Url.createObjectUrlFromBlob(blob);

  var opened = false;
  try {
    final w = web.window.open(url, '_blank');
    opened = (w as dynamic) != null;
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    final a = web.AnchorElement(href: url)
      ..target = '_blank'
      ..download = fileName;
    web.document.body?.append(a);
    a.click();
    a.remove();
  }
  Timer(const Duration(minutes: 5), () => web.Url.revokeObjectUrl(url));
}
