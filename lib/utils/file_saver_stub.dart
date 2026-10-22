import 'dart:typed_data';

/// نسخة الويب: FilePicker.saveFile نفسه يبدأ تنزيل الملف مباشرة عبر
/// المتصفح بمجرد تمرير bytes، فلا حاجة لأي كتابة يدوية إضافية هنا.
Future<void> writeBytesToPath(String path, Uint8List bytes) async {
  // لا شيء مطلوب على الويب.
}
