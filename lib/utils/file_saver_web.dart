// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as web;
import 'dart:typed_data';

import 'file_saver_stub.dart' show SaveResult;
export 'file_saver_stub.dart' show SaveResult;

/// الويب: FilePicker.saveFile غير منفَّذ على الويب في الإصدار المستخدم (8.x) ويرمي
/// UnimplementedError، وهذا كان سبب «حدث خطأ أثناء التصدير». نُنزّل الملف مباشرة
/// بواجهات المتصفح: Blob + Object URL + رابط <a download>، دون أي واجهة خاصة بنظام تشغيل.
Future<SaveResult> saveBytesAsFile({
  required String fileName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
  String dialogTitle = 'حفظ الملف',
}) async {
  final blob = web.Blob(<dynamic>[bytes], mimeType);
  final url = web.Url.createObjectUrlFromBlob(blob);
  try {
    final a = web.AnchorElement(href: url)
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
  } finally {
    // نترك للمتصفح وقتًا لبدء التنزيل قبل تحرير الرابط.
    Timer(const Duration(seconds: 30), () => web.Url.revokeObjectUrl(url));
  }
  return const SaveResult(saved: true);
}
