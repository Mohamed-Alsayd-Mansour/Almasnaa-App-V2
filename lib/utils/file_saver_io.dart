import 'dart:io';
import 'dart:typed_data';

/// نسخة الأنظمة التي تملك نظام ملفات حقيقيًا (Android، iOS، Windows،
/// Linux، macOS). بعض إصدارات FilePicker.saveFile لا تكتب الملف
/// فعليًا على سطح المكتب حتى مع تمرير bytes، لذا نكتبه هنا بأنفسنا
/// لضمان نجاح الحفظ على كل هذه المنصات دون استثناء.
Future<void> writeBytesToPath(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes);
}
