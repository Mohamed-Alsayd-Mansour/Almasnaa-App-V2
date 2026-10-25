// حفظ/تنزيل ملف حسب المنصة (استيراد مشروط حتى لا يكسر dart:io أو dart:html بناء أي منصة):
//  • الويب: تنزيل عبر Blob ورابط <a download> من المتصفح مباشرة (file_saver_web.dart).
//  • المنصات ذات نظام الملفات (Android/iOS/Windows/...): نافذة الحفظ الأصلية ثم كتابة الملف (file_saver_io.dart).
export 'file_saver_stub.dart'
    if (dart.library.html) 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_io.dart';
